import Foundation

/// What the app's send closure reports back about one batch.
///
/// The sink never reads HTTP. The app maps its own responses onto these three cases, and each
/// case decides what happens to the batch.
///
/// | Case | The batch | Next attempt |
/// |---|---|---|
/// | ``delivered`` | Removed from the spool | After ``BatchPolicy/minimumInterval`` |
/// | ``rejected`` | **Removed, unsent** — sending it again would only be refused again | After ``BatchPolicy/minimumInterval`` |
/// | ``retryLater(after:)`` | Kept | After the longer of the given wait and ``BatchPolicy/minimumInterval`` |
///
/// Throwing from the closure means the batch never reached anyone (offline, timed out). It is
/// kept, as with ``retryLater(after:)`` with no wait given.
///
/// A typical mapping: `2xx` is ``delivered``, `400` and `413` are ``rejected``, `429` and `5xx`
/// are ``retryLater(after:)`` with the `Retry-After` header if there is one.
public enum BatchOutcome: Sendable, Equatable {

    /// The receiver took the batch.
    case delivered

    /// The receiver refused the batch as malformed. It is thrown away.
    case rejected

    /// The receiver is busy or failing. The batch is kept for a later attempt.
    case retryLater(after: Duration?)
}

/// How much goes in one batch, how much is kept while sending is impossible, and how often to try.
///
/// The defaults are the ones the first-party receiver in `tabisaki` enforces: 100 events and
/// 64 KB per request, 500 kept on the device, and nothing sent within 60 seconds of the last try.
public struct BatchPolicy: Sendable, Equatable {

    /// Most events in one batch.
    public var maxEvents: Int

    /// Most bytes in one request body, header included. An event that cannot fit in a batch on
    /// its own is thrown away rather than blocking the spool for good.
    public var maxBytes: Int

    /// Most events kept on the device. Past it, **the oldest are dropped first**.
    public var capacity: Int

    /// A spool this long sends itself without waiting for ``AnalyticsBatchSink/flush()``.
    public var flushThreshold: Int

    /// No attempt starts sooner than this after the previous one.
    public var minimumInterval: Duration

    public init(
        maxEvents: Int = 100,
        maxBytes: Int = 65_536,
        capacity: Int = 500,
        flushThreshold: Int = 100,
        minimumInterval: Duration = .seconds(60)
    ) {
        self.maxEvents = maxEvents
        self.maxBytes = maxBytes
        self.capacity = capacity
        self.flushThreshold = flushThreshold
        self.minimumInterval = minimumInterval
    }

    /// 100 events, 64 KB, 500 kept, sends itself at 100, 60 seconds between attempts.
    public static let standard = BatchPolicy()
}

/// The JSON keys a batch is written with.
///
/// The defaults produce this, with the header's fields and the person's properties at the top
/// level:
///
/// ```json
/// {
///   "install": "ins_8f2c…", "plan": "free",
///   "events": [
///     { "id": "…", "name": "paywall_shown", "at": 1790000000.0,
///       "params": { "placement": "settings" } }
///   ]
/// }
/// ```
///
/// Anything returned by the sink's `stamp` closure sits next to `id` and `name` in each event.
/// When a stamp, a header field, or a property uses the same key as something the sink writes,
/// the sink's own key wins.
public struct BatchFormat: Sendable, Equatable {

    /// How the time an event happened is written.
    public enum Time: Sendable, Equatable {
        /// Seconds since 1970 as a fractional number.
        case seconds
        /// Milliseconds since 1970 as a whole number.
        case milliseconds
    }

    public var eventsKey: String
    public var idKey: String
    public var nameKey: String
    public var timeKey: String
    public var time: Time
    public var parametersKey: String

    /// Where the person's properties go. `nil` puts each one at the top level of the batch.
    public var propertiesKey: String?

    public init(
        eventsKey: String = "events",
        idKey: String = "id",
        nameKey: String = "name",
        timeKey: String = "at",
        time: Time = .seconds,
        parametersKey: String = "params",
        propertiesKey: String? = nil
    ) {
        self.eventsKey = eventsKey
        self.idKey = idKey
        self.nameKey = nameKey
        self.timeKey = timeKey
        self.time = time
        self.parametersKey = parametersKey
        self.propertiesKey = propertiesKey
    }

    /// `events` / `id` / `name` / `at` in seconds / `params`, properties at the top level.
    public static let standard = BatchFormat()
}

/// What one call to ``AnalyticsBatchSink/flush()`` did.
public struct FlushReport: Sendable, Equatable {

    /// Why the call stopped.
    public enum Status: Sendable, Equatable {
        /// Everything in the spool was sent or thrown away.
        case emptied
        /// The previous attempt was too recent, so nothing was tried.
        case throttled(until: Date)
        /// Another flush was already running, so nothing was tried.
        case busy
        /// A batch could not be delivered. What is left is kept until this time.
        case deferred(until: Date)
    }

    public let status: Status

    /// Events the receiver took.
    public let delivered: Int

    /// Events thrown away unsent: refused batches, and events too large for any batch.
    public let discarded: Int

    /// Events still in the spool.
    public let remaining: Int
}
