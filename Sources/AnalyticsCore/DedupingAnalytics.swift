import Foundation

/// Applies the catalog's counting rule before forwarding, so no firing point has to ask whether
/// it already fired.
///
/// Without this layer, `guard alreadyFired == false else { return }` ends up at the firing point.
/// For an event fired from two places, the same check is scattered across both, and only one of
/// them gets fixed. The catalog already holds the counting rule, so enforcing it collapses into
/// one place as well.
///
/// ```swift
/// let analytics = DedupingAnalytics(MultiplexAnalytics([ConsoleAnalytics(), firebase]))
/// ```
///
/// ## What each scope means here
///
/// | Scope | Handling |
/// |---|---|
/// | ``DedupScope/install`` | A flag in `UserDefaults` under `analytics.fired.<key>`, so the window spans launches and closes for good. Losing the store costs one extra count |
/// | ``DedupScope/session`` | A set held by this instance, so the window is this object's lifetime — in an app, the process |
/// | ``DedupScope/always`` | Straight through |
///
/// Every case is handled here, so a scope added to ``DedupScope`` without a window to enforce
/// stops the build rather than passing straight through unnoticed.
///
/// A repeat inside a closed window is dropped in silence: nothing is forwarded, nothing is
/// counted anywhere, and ``track(_:)`` returns exactly as it does for an event that was sent.
///
/// Which occurrences count as the same one is decided by ``AnalyticsEvent/dedupKey``, which by
/// default is the name alone — two occurrences differing only in their parameters collapse
/// together.
///
/// User properties (``AnalyticsUserProperty``) are never thinned out. A property is current
/// state, so setting the same value again changes nothing, and dropping the repeat would leave a
/// stale value in place after a restore.
public final class DedupingAnalytics: AnalyticsClient, @unchecked Sendable {

    private let wrapped: any AnalyticsClient
    private let defaults: UserDefaults

    /// Guards the session set, and keeps the install flag's read-then-write from interleaving.
    ///
    /// This one piece of mutable state is why `Sendable` is vouched for by hand here, and
    /// ``track(_:)`` is the only path that reaches it.
    private let lock = NSLock()
    private var firedThisSession: Set<String> = []

    /// - Parameters:
    ///   - wrapped: Where the occurrences that survive are actually sent
    ///   - defaults: Where ``DedupScope/install`` flags are kept. Tests pass a suite of their own,
    ///     since the flags never expire on their own
    public init(_ wrapped: any AnalyticsClient, defaults: UserDefaults = .standard) {
        self.wrapped = wrapped
        self.defaults = defaults
    }

    public func track(_ event: any AnalyticsEvent) {
        guard shouldSend(event) else { return }
        wrapped.track(event)
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        wrapped.setUserProperty(property)
    }

    private func shouldSend(_ event: any AnalyticsEvent) -> Bool {
        switch event.dedup {
        case .always:
            return true
        case .session:
            lock.lock()
            defer { lock.unlock() }
            return firedThisSession.insert(event.dedupKey).inserted
        case .install:
            let key = Self.installKey(for: event.dedupKey)
            lock.lock()
            defer { lock.unlock() }
            guard !defaults.bool(forKey: key) else { return false }
            defaults.set(true, forKey: key)
            return true
        }
    }

    static func installKey(for dedupKey: String) -> String {
        "analytics.fired.\(dedupKey)"
    }
}
