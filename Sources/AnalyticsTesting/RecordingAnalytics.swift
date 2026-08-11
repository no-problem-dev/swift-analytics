import AnalyticsCore
import Foundation

/// A test double that only remembers what it was asked to send.
///
/// Use it to pin "this interaction produces these occurrences, **in this order, this many
/// times**" in a test. Looking at the count is the point — measurement accidents are usually one
/// too many rather than none, and one too many is invisible to a check that only looks at which
/// names appeared.
///
/// Safe to call from any thread: a lock serialises every read and write, so a client called from
/// a background task records correctly. It is not an actor and never hops to the main actor, so a
/// read taken immediately after an asynchronous send may not include that send yet.
///
/// ```swift
/// let analytics = RecordingAnalytics()
/// // ... interact ...
/// #expect(analytics.names == ["tutorial_begin", "tutorial_complete"])
/// ```
public final class RecordingAnalytics: AnalyticsClient, @unchecked Sendable {

    /// Guards the records. These two pieces of mutable state are why `Sendable` is vouched for by
    /// hand here, and nothing outside this file reaches them.
    private let lock = NSLock()
    private var storedEvents: [any AnalyticsEvent] = []
    private var storedProperties: [any AnalyticsUserProperty] = []

    public init() {}

    /// Everything that was sent, in the order it was sent.
    public var events: [any AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    /// The names of what was sent, in order. **Repeats are left in.**
    public var names: [String] {
        events.map(\.name)
    }

    /// One line per occurrence, for pinning the parameter values as well as the names.
    ///
    /// Each line takes the form `name key=value`, with parameters sorted by key.
    public var lines: [String] {
        events.map(\.debugLine)
    }

    /// Every property that was set, in the order it was set, repeats included.
    public var properties: [any AnalyticsUserProperty] {
        lock.lock()
        defer { lock.unlock() }
        return storedProperties
    }

    /// One line per property, in the form `name=value`.
    public var propertyLines: [String] {
        properties.map { "\($0.name)=\($0.value)" }
    }

    /// How many times something with this name was sent. **Use it to pin exactly once.**
    public func count(of name: String) -> Int {
        names.filter { $0 == name }.count
    }

    public func track(_ event: any AnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.append(event)
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        lock.lock()
        defer { lock.unlock() }
        storedProperties.append(property)
    }

    /// Throws away both records, for separating one phase from the next within a single test.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.removeAll()
        storedProperties.removeAll()
    }
}
