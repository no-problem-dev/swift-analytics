import Foundation
import os

/// The person's own off switch for measurement, placed in front of everything else.
///
/// While it is off, every occurrence and every property is dropped before it reaches anything —
/// not deduplicated, not buffered, not written anywhere. Turning it off also runs `onDisable`,
/// which is where the app erases what had already been collected but not yet sent (a buffered
/// batch, crash reports waiting on disk, the measurement install ID).
///
/// ```swift
/// let sink = AnalyticsBatchSink(directory: eventsDirectory, send: post)
/// let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) {
///     await sink.purge()
/// }
///
/// // Settings screen: the stop is immediate, the erasure follows in a task
/// Toggle("Share usage", isOn: Binding(get: { analytics.isEnabled }, set: { analytics.setEnabled($0) }))
/// ```
///
/// ## Put it outermost
///
/// Wrap ``DedupingAnalytics`` with this, not the other way round. Inside, an occurrence fired
/// while measurement is off would still use up its ``DedupScope/install`` window, and the first
/// real occurrence after turning it back on would then never be sent.
///
/// ## The choice survives relaunch
///
/// The state is kept in `UserDefaults` under ``defaultsKey``, and read back when the switch is
/// made. **An app that builds the switch at launch cannot forget to restore the person's choice**,
/// which is the failure that matters here: sending once after someone said no.
///
/// With nothing stored, the switch is on (measurement is opt-out). Pass `enabledByDefault: false`
/// for an app that asks first.
public final class AnalyticsSwitch: AnalyticsClient, Sendable {

    /// The `UserDefaults` key the choice is stored under.
    public static let defaultsKey = "analytics.sendingEnabled"

    private let wrapped: any AnalyticsClient
    private let onDisable: @Sendable () async -> Void
    private let enabled: OSAllocatedUnfairLock<Bool>

    /// Where the choice is kept.
    ///
    /// `UserDefaults` is documented as thread-safe but this SDK does not mark it `Sendable`, so
    /// this one property opts out of the check — the type as a whole does not.
    nonisolated(unsafe) private let defaults: UserDefaults

    /// - Parameters:
    ///   - wrapped: Where occurrences go while the switch is on
    ///   - defaults: Where the choice is kept. Tests pass a suite of their own
    ///   - enabledByDefault: The state when nothing has been stored yet. `true` is opt-out
    ///   - onDisable: Erases what was collected but not sent. Runs every time the switch is set
    ///     off, so an erasure cut short by the app being killed is finished by the next attempt
    public init(
        _ wrapped: any AnalyticsClient,
        defaults: UserDefaults = .standard,
        enabledByDefault: Bool = true,
        onDisable: @escaping @Sendable () async -> Void = {}
    ) {
        self.wrapped = wrapped
        self.defaults = defaults
        self.onDisable = onDisable
        let stored = defaults.object(forKey: Self.defaultsKey) as? Bool
        self.enabled = OSAllocatedUnfairLock(initialState: stored ?? enabledByDefault)
    }

    /// Whether occurrences are currently let through.
    public var isEnabled: Bool {
        enabled.withLock { $0 }
    }

    /// Turns measurement on or off, and remembers the choice.
    ///
    /// Turning it off stops occurrences first and erases second, so nothing fired while the
    /// erasure runs can slip in behind it. Returns once `onDisable` has finished.
    public func setEnabled(_ isEnabled: Bool) async {
        store(isEnabled)
        if !isEnabled {
            await onDisable()
        }
    }

    /// Turns measurement on or off from synchronous code — a toggle's action — and remembers the choice.
    ///
    /// **The stop takes effect before this returns**, so an occurrence tracked on the next line is
    /// already dropped. Wrapping the `async` overload in `Task { … }` instead leaves a gap: the task
    /// has not started yet when the next occurrence arrives, and that one gets through.
    ///
    /// Only the erasure (`onDisable`) runs later, in the returned task; await its `value` where the
    /// erasure has to be finished (a test, a "delete my data" screen). Turning it on returns a task
    /// that is already done.
    @discardableResult
    public func setEnabled(_ isEnabled: Bool) -> Task<Void, Never> {
        store(isEnabled)
        guard !isEnabled else { return Task {} }
        let onDisable = onDisable
        return Task { await onDisable() }
    }

    private func store(_ isEnabled: Bool) {
        enabled.withLock { $0 = isEnabled }
        defaults.set(isEnabled, forKey: Self.defaultsKey)
    }

    public func track(_ event: any AnalyticsEvent) {
        guard isEnabled else { return }
        wrapped.track(event)
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        guard isEnabled else { return }
        wrapped.setUserProperty(property)
    }
}
