/// The one outlet an app sends measurements through.
///
/// Implementations (Firebase, PostHog, your own server) stay out of this package. Swift Package
/// Manager resolves dependencies per package, so depending on a vendor here would **drop that
/// vendor's SDK onto consumers that only wanted the vocabulary**.
///
/// Write the adapter in about 20 lines inside the app, or add it from a separate package such as
/// `swift-analytics-firebase`.
///
/// ## Sending is fire-and-forget
///
/// Nothing here returns a value or throws. There is no path along which a failed or slow send can
/// reach the app's behaviour — "stop what the person is doing because a log would not go out" is
/// never worth it.
public protocol AnalyticsClient: Sendable {

    /// Sends one occurrence, with no result to inspect and no failure to handle.
    ///
    /// One call is one logged event. This protocol never merges, buffers, or drops anything;
    /// counting rules are applied by ``DedupingAnalytics``, which wraps a client and honours the
    /// event's ``AnalyticsEvent/dedup`` before forwarding.
    func track(_ event: any AnalyticsEvent)

    /// Replaces the current value of an attribute carried by the person.
    ///
    /// Setting the same value again changes nothing, so it is safe to call wherever the state
    /// happens to be known. Properties are never deduped, at any layer.
    func setUserProperty(_ property: any AnalyticsUserProperty)
}

/// A client that discards everything, used in tests, previews, and builds with no vendor key set.
///
/// It states in the type system that measurement can be absent without anything in the app
/// breaking.
public struct NoopAnalytics: AnalyticsClient {

    public init() {}

    public func track(_ event: any AnalyticsEvent) {}

    public func setUserProperty(_ property: any AnalyticsUserProperty) {}
}

/// Fans every occurrence out to several destinations at once.
///
/// Use it during development to watch events in the console while still sending them for real,
/// and during a move between destinations, where both have to run for a while so the history
/// does not end up with a hole in it.
public struct MultiplexAnalytics: AnalyticsClient {

    private let clients: [any AnalyticsClient]

    /// - Parameter clients: Destinations to forward to. **Called in the order given, one after
    ///   another on the calling thread.**
    public init(_ clients: [any AnalyticsClient]) {
        self.clients = clients
    }

    public func track(_ event: any AnalyticsEvent) {
        for client in clients { client.track(event) }
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        for client in clients { client.setUserProperty(property) }
    }
}
