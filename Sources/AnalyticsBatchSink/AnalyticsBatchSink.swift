import AnalyticsCore
import Foundation
import os

/// A destination that keeps occurrences in a file on the device and sends them in batches to the
/// app's own receiver, **always in the one envelope** described in `Schema/common/ENVELOPE.md`.
///
/// The app hands over where to send, how to authorize, and its name — nothing about the shape:
///
/// ```swift
/// let sink = AnalyticsBatchSink(
///     app: "kotoakari",
///     endpoint: URL(string: "https://api.example.com/v1/events")!,
///     authorize: { ["Authorization": "Bearer \(try await auth.idToken())"] },
///     uid: { Auth.auth().currentUser?.uid }      // leave out when behaviour is not tied to purchases
/// )
/// let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) { await sink.purge() }
/// FirstLaunch.recordLaunch(sendingTo: analytics)
///
/// // After launch, and when the scene moves to the background
/// await sink.flush()
/// ```
///
/// A batch goes out like this:
///
/// ```json
/// { "schema_version": 1, "app": "kotoakari", "install_id": "8c1f…", "uid": "…",
///   "app_version": "1.2.0", "build": "45", "channel": "appstore", "lang": "ja", "region": "JP",
///   "sent_at": 1762560000000,
///   "events": [ { "id": "…", "name": "paywall_shown", "occurred_at": 1762559990000,
///                 "props": { "source": "onboarding" } } ] }
/// ```
///
/// There is no setting for the keys or the unit of time. Up to 0.2 they could be chosen, and the
/// apps ended up with seven different shapes.
///
/// ## What is kept and when it goes
///
/// - Each occurrence is given an `id` (a UUID) and the time it happened (`occurred_at`, ms) as it
///   is tracked, along with the app version, build, and uid at that moment. The receiver uses the
///   `id` to keep a batch that arrives twice from counting twice
/// - The spool is a JSON file in `directory`, written off the calling thread after each change,
///   and read back when the sink is made. Past ``BatchPolicy/capacity`` the oldest are dropped
/// - ``flush()`` sends batches of up to ``BatchPolicy/maxEvents`` and ``BatchPolicy/maxBytes``
///   until the spool is empty or one fails. Events tracked under another app version, build, or
///   uid go in a batch of their own, since the head carries one of each. Reaching
///   ``BatchPolicy/flushThreshold`` starts a flush by itself
/// - **No attempt starts within ``BatchPolicy/minimumInterval`` of the previous one**, whoever
///   asked. Nothing here wakes the device or schedules background work; what is not sent goes
///   with the next flush
/// - How a response is read is fixed: see the table on the outcome of a batch in the
///   documentation of this module
///
/// ## Properties are not sent
///
/// The envelope has no place for `AnalyticsUserProperty`, so ``setUserProperty(_:)`` does
/// nothing here. State such as the plan is the server's (RevenueCat for purchases); send a
/// property to a destination that keeps them, through `MultiplexAnalytics`.
///
/// ## Why a class and not an actor
///
/// ``track(_:)`` is synchronous, as the `AnalyticsClient` port requires. Hopping onto an actor
/// from there would take a task per occurrence, and tasks do not keep the order they were made in
/// — two taps would reach the spool in either order. The spool is appended to in place under a
/// lock instead, and only the file and the network are left to run elsewhere.
public final class AnalyticsBatchSink: AnalyticsClient, Sendable {

    private let state: OSAllocatedUnfairLock<SpoolState>
    private let file: SpoolFile
    private let layout: BatchLayout
    private let policy: BatchPolicy
    private let app: String
    private let endpoint: URL
    private let authorize: @Sendable () async throws -> [String: String]
    private let uid: @Sendable () -> String?
    private let context: @Sendable () -> EnvelopeContext
    private let transport: BatchTransport
    private let makeID: @Sendable () -> String
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - app: The app's short name in snake_case (`kotoakari`). The receiver tells products
    ///     apart by it
    ///   - endpoint: Where batches are posted
    ///   - authorize: Header fields for each request, asked for just before it is sent — usually
    ///     `Authorization`. Throw when none can be made now; the batch is kept for later
    ///   - uid: The signed-in person's uid, read as each event is tracked. Leave it out for apps
    ///     that do not tie behaviour to purchases
    ///   - directory: Where the spool file (`events.json`) is kept. Created when first needed.
    ///     Give the sink a directory of its own
    ///   - policy: Batch sizes, how much to keep, how often to try
    ///   - context: The head of the envelope that describes the device. Read as each event is
    ///     tracked (app version and build) and as each batch is laid out (the rest)
    ///   - transport: How a request goes out
    ///   - makeID: The `id` each event is given
    ///   - now: The clock, for `occurred_at`, `sent_at`, and spacing attempts
    public init(
        app: String,
        endpoint: URL,
        authorize: @escaping @Sendable () async throws -> [String: String] = { [:] },
        uid: @escaping @Sendable () -> String? = { nil },
        directory: URL = URL.applicationSupportDirectory.appending(path: "swift-analytics/events"),
        policy: BatchPolicy = .standard,
        context: @escaping @Sendable () -> EnvelopeContext = { .current() },
        transport: BatchTransport = .urlSession,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(
            app.wholeMatch(of: /[a-z][a-z0-9_]*/) != nil,
            "AnalyticsBatchSink: app は snake_case の短い名前（\(app)）"
        )
        let file = SpoolFile(directory: directory)
        var initial = SpoolState(events: file.load())
        initial.trim(to: policy.capacity)
        self.state = OSAllocatedUnfairLock(initialState: initial)
        self.file = file
        self.layout = BatchLayout(policy: policy)
        self.policy = policy
        self.app = app
        self.endpoint = endpoint
        self.authorize = authorize
        self.uid = uid
        self.context = context
        self.transport = transport
        self.makeID = makeID
        self.now = now
    }

    // MARK: - AnalyticsClient

    public func track(_ event: any AnalyticsEvent) {
        let device = context()
        let spooled = SpooledEvent(
            id: makeID(),
            name: event.name,
            occurredAt: BatchLayout.milliseconds(now()),
            props: event.parameters.mapValues(WireValue.init),
            appVersion: device.appVersion,
            build: device.build,
            uid: uid()
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

    /// Does nothing: the envelope carries no properties (see "Properties are not sent").
    public func setUserProperty(_ property: any AnalyticsUserProperty) {}

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
            let candidates = state.withLock { state -> [SpooledEvent] in
                guard let origin = state.events.first?.origin else { return [] }
                return Array(state.events.prefix(policy.maxEvents).prefix { $0.origin == origin })
            }
            guard let origin = candidates.first?.origin else { break }

            let header = layout.header(app: app, context: context(), origin: origin, sentAt: now())
            guard let batch = try? layout.batch(of: candidates, header: header) else { break }
            if !batch.oversized.isEmpty {
                remove(batch.oversized)
                discarded += batch.oversized.count
            }
            guard !batch.included.isEmpty else { continue }

            let attempt = now()
            state.withLock { $0.notBefore = attempt.addingTimeInterval(interval) }
            let outcome: BatchOutcome
            do {
                outcome = try await post(batch.body)
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

    /// Erases everything kept from memory and from the file.
    ///
    /// For turning measurement off (`AnalyticsSwitch`) and for deleting an
    /// account. A batch already on its way when this runs may still arrive.
    public func purge() async {
        state.withLock { state in
            state.events.removeAll()
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

    private func post(_ body: Data) async throws -> BatchOutcome {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in try await authorize() {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let response = try await transport.perform(request)
        return BatchOutcome(status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
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
