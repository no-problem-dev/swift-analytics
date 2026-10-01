import AnalyticsCore
import Foundation
import os

/// A destination that keeps occurrences in a file on the device and sends them in batches.
///
/// It owns three things — **keeping, batching, and trying again** — and nothing about where the
/// batches go. The URL, authentication, and how a response is read are the app's, handed in as
/// one closure that takes a request body and says what became of it:
///
/// ```swift
/// let sink = AnalyticsBatchSink(
///     directory: appSupport.appending(path: "AppData/events"),
///     header: { await telemetryHeader() },          // install ID, app version, plan, …
///     send: { body in try await server.postEvents(body) }   // -> BatchOutcome
/// )
/// let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) { await sink.purge() }
///
/// // After launch, and when the scene moves to the background
/// await sink.flush()
/// ```
///
/// ## What is kept and when it goes
///
/// - Each occurrence is given an ID (``BatchFormat/idKey``) and the time it happened as it is
///   tracked, so a batch that reaches the receiver twice can be told apart from two occurrences
/// - The spool is a JSON file in `directory`, written off the calling thread after each change,
///   and read back when the sink is made. Past ``BatchPolicy/capacity`` the oldest are dropped
/// - ``flush()`` sends batches of up to ``BatchPolicy/maxEvents`` and ``BatchPolicy/maxBytes``
///   until the spool is empty or one fails. Reaching ``BatchPolicy/flushThreshold`` starts a
///   flush by itself
/// - **No attempt starts within ``BatchPolicy/minimumInterval`` of the previous one**, whoever
///   asked. Nothing here wakes the device or schedules background work; what is not sent goes
///   with the next flush
///
/// The person's properties (``AnalyticsUserProperty``) are not events. The latest value of each
/// is kept and written into the head of every batch, so the receiver reads the current state
/// once per batch rather than once per event.
///
/// ## Why a class and not an actor
///
/// ``track(_:)`` is synchronous, as the ``AnalyticsClient`` port requires. Hopping onto an actor
/// from there would take a task per occurrence, and tasks do not keep the order they were made in
/// — two taps would reach the spool in either order. The spool is appended to in place under a
/// lock instead, and only the file and the network are left to run elsewhere.
public final class AnalyticsBatchSink: AnalyticsClient, Sendable {

    private let state: OSAllocatedUnfairLock<SpoolState>
    private let file: SpoolFile
    private let layout: BatchLayout
    private let policy: BatchPolicy
    private let header: @Sendable () async -> [String: AnalyticsValue]
    private let stamp: @Sendable (any AnalyticsEvent, Date) -> [String: AnalyticsValue]
    private let makeID: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let send: @Sendable (Data) async throws -> BatchOutcome

    /// - Parameters:
    ///   - directory: Where the spool file (`events.json`) is kept. Created when first needed.
    ///     Give the sink a directory of its own
    ///   - policy: Batch sizes, how much to keep, how often to try
    ///   - format: The JSON keys a batch is written with
    ///   - header: Fields for the head of each batch, asked for when the batch is laid out —
    ///     install ID, app and OS version, catalog version, and the like
    ///   - stamp: Extra fields for each event, decided when it is tracked, such as days since
    ///     install. Never anything a person wrote
    ///   - makeID: The ID each event is given
    ///   - now: The clock, for the time an event happened and for spacing attempts
    ///   - send: Posts one body and reports what became of it. Throw when it never arrived
    public init(
        directory: URL,
        policy: BatchPolicy = .standard,
        format: BatchFormat = .standard,
        header: @escaping @Sendable () async -> [String: AnalyticsValue] = { [:] },
        stamp: @escaping @Sendable (any AnalyticsEvent, Date) -> [String: AnalyticsValue] = { _, _ in [:] },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> Date = { Date() },
        send: @escaping @Sendable (Data) async throws -> BatchOutcome
    ) {
        let file = SpoolFile(directory: directory)
        let stored = file.load()
        var initial = SpoolState(events: stored.events, properties: stored.properties)
        initial.trim(to: policy.capacity)
        self.state = OSAllocatedUnfairLock(initialState: initial)
        self.file = file
        self.layout = BatchLayout(format: format, policy: policy)
        self.policy = policy
        self.header = header
        self.stamp = stamp
        self.makeID = makeID
        self.now = now
        self.send = send
    }

    // MARK: - AnalyticsClient

    public func track(_ event: any AnalyticsEvent) {
        let moment = now()
        let spooled = SpooledEvent(
            id: makeID(),
            name: event.name,
            at: moment.timeIntervalSince1970,
            parameters: event.parameters.mapValues(WireValue.init),
            stamp: stamp(event, moment).mapValues(WireValue.init)
        )
        let capacity = policy.capacity
        let threshold = policy.flushThreshold
        let startsFlush = state.withLock { state -> Bool in
            state.events.append(spooled)
            state.trim(to: capacity)
            state.generation += 1
            guard state.events.count >= threshold, !state.isAutoFlushPending else { return false }
            state.isAutoFlushPending = true
            return true
        }
        scheduleSave()
        if startsFlush {
            Task {
                _ = await self.flush()
                self.state.withLock { $0.isAutoFlushPending = false }
            }
        }
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        let name = property.name
        let value = WireValue.string(property.value)
        let changed = state.withLock { state -> Bool in
            guard state.properties[name] != value else { return false }
            state.properties[name] = value
            state.generation += 1
            return true
        }
        if changed { scheduleSave() }
    }

    // MARK: - Sending

    /// Sends what is kept, a batch at a time, until the spool is empty or a batch fails.
    ///
    /// Call it after launch and when the app moves to the background. It does nothing — and says
    /// so in the report — while another flush is running or within
    /// ``BatchPolicy/minimumInterval`` of the last attempt.
    @discardableResult
    public func flush() async -> FlushReport {
        let started = now()
        let claim = state.withLock { state -> FlushReport.Status? in
            if state.isFlushing { return .busy }
            if let notBefore = state.notBefore, started < notBefore { return .throttled(until: notBefore) }
            state.isFlushing = true
            return nil
        }
        if let claim {
            return FlushReport(status: claim, delivered: 0, discarded: 0, remaining: pendingCount)
        }

        var delivered = 0
        var discarded = 0
        var status = FlushReport.Status.emptied
        let interval = policy.minimumInterval.timeInterval

        while true {
            let (candidates, properties) = state.withLock { state in
                (Array(state.events.prefix(policy.maxEvents)), state.properties)
            }
            guard !candidates.isEmpty else { break }

            let fields = await header()
            guard let batch = try? layout.batch(
                of: candidates, header: layout.header(fields: fields, properties: properties)
            ) else { break }
            if !batch.oversized.isEmpty {
                remove(batch.oversized)
                discarded += batch.oversized.count
            }
            guard !batch.included.isEmpty else { continue }

            let attempt = now()
            state.withLock { $0.notBefore = attempt.addingTimeInterval(interval) }
            let outcome: BatchOutcome
            do {
                outcome = try await send(batch.body)
            } catch {
                status = .deferred(until: attempt.addingTimeInterval(interval))
                break
            }
            switch outcome {
            case .delivered:
                remove(batch.included)
                delivered += batch.included.count
                continue
            case .rejected:
                remove(batch.included)
                discarded += batch.included.count
                continue
            case let .retryLater(after):
                let wait = max(after?.timeInterval ?? 0, interval)
                let until = now().addingTimeInterval(wait)
                state.withLock { $0.notBefore = until }
                status = .deferred(until: until)
            }
            break
        }

        state.withLock { $0.isFlushing = false }
        await save()
        return FlushReport(status: status, delivered: delivered, discarded: discarded, remaining: pendingCount)
    }

    /// Erases everything kept — events and properties — from memory and from the file.
    ///
    /// For turning measurement off (``AnalyticsCore/AnalyticsSwitch``) and for deleting an
    /// account. A batch already on its way when this runs may still arrive.
    public func purge() async {
        state.withLock { state in
            state.events.removeAll()
            state.properties.removeAll()
            state.notBefore = nil
            state.generation += 1
        }
        await save()
    }

    /// Writes what is kept to the file now, without waiting for the write already queued.
    public func save() async {
        await file.persist(from: state)
    }

    /// How many events are kept and not yet sent.
    public var pendingCount: Int {
        state.withLock { $0.events.count }
    }

    private func remove(_ ids: [String]) {
        let doomed = Set(ids)
        state.withLock { state in
            state.events.removeAll { doomed.contains($0.id) }
            state.generation += 1
        }
    }

    private func scheduleSave() {
        let file = file
        let state = state
        Task { await file.persist(from: state) }
    }
}
