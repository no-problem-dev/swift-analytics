import AnalyticsCore
import Foundation

/// What the device says about itself in the head of every batch (`Schema/common/ENVELOPE.md`).
///
/// ``current(defaults:bundle:locale:)`` fills it from the running app; tests and previews make one
/// by hand.
public struct EnvelopeContext: Sendable, Equatable {

    /// `InstallID`.
    public var installID: String
    /// `CFBundleShortVersionString`.
    public var appVersion: String
    /// `CFBundleVersion`.
    public var build: String
    /// `BuildChannel`.
    public var channel: BuildChannel
    /// The device's language as a BCP 47 tag: the language code, and the script where it tells
    /// writings apart — `ja`, `en`, `zh-Hans`, `zh-Hant`. See ``languageTag(of:)``.
    public var lang: String
    /// The device's region (`Locale.current.region`), such as `JP`.
    public var region: String

    public init(installID: String, appVersion: String, build: String, channel: BuildChannel, lang: String, region: String) {
        self.installID = installID
        self.appVersion = appVersion
        self.build = build
        self.channel = channel
        self.lang = lang
        self.region = region
    }

    /// Read from the running app. An item it cannot find is sent as an empty string.
    public static func current(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> EnvelopeContext {
        let info = bundle.infoDictionary ?? [:]
        return EnvelopeContext(
            installID: InstallID.current(defaults: defaults),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            channel: .current,
            lang: languageTag(of: locale),
            region: locale.region?.identifier ?? ""
        )
    }
}

extension EnvelopeContext {

    /// The `lang` of the envelope for a locale: the language code, followed by the script where
    /// the script tells writings apart.
    ///
    /// Chinese always carries its script, so Simplified and Traditional stay apart: `zh-Hans_CN`
    /// and `zh_CN` give `zh-Hans`, `zh-Hant_TW` and `zh_TW` give `zh-Hant`. Any other language
    /// carries it only when it is not the language's usual one (`sr-Latn_RS` gives `sr-Latn`);
    /// `ja_JP` gives `ja` and `en_US` gives `en`, as before. The region is not part of it: it goes
    /// in `region`.
    public static func languageTag(of locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier else { return "" }
        guard let script = locale.language.script?.identifier else { return code }
        let usual = Locale.Language(identifier: code).script?.identifier
        // Foundation folds `zh-Hans_CN` into `zh_CN`, so the script has to be put back from the
        // language rather than read from the identifier
        guard code == "zh" || script != usual else { return code }
        return "\(code)-\(script)"
    }
}

/// How a request body reaches the receiver. ``urlSession`` unless a test puts something else in.
public struct BatchTransport: Sendable {

    let perform: @Sendable (URLRequest) async throws -> HTTPURLResponse

    /// - Parameter perform: Sends the request and returns the response. Throw when it never
    ///   arrived (offline, timed out)
    public init(_ perform: @escaping @Sendable (URLRequest) async throws -> HTTPURLResponse) {
        self.perform = perform
    }

    /// `URLSession.shared`.
    public static let urlSession = BatchTransport { request in
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return http
    }
}

/// What became of one batch, read from the receiver's response.
///
/// | Response | The batch | Next attempt |
/// |---|---|---|
/// | `2xx` | Removed from the spool | After ``BatchPolicy/minimumInterval`` |
/// | `401`・`403`・`408`・`429`・`5xx` | Kept | After the longer of `Retry-After` and ``BatchPolicy/minimumInterval`` |
/// | Any other status | **Removed, unsent** — sending it again would only be refused again | After ``BatchPolicy/minimumInterval`` |
///
/// No response at all (offline, timed out, the authorization closure threw) keeps the batch, as
/// with a retry and no `Retry-After`. `401` and `403` are kept rather than dropped: a token that
/// failed to refresh should not cost the events.
enum BatchOutcome: Sendable, Equatable {
    case delivered
    case rejected
    case retryLater(after: Duration?)

    init(status: Int, retryAfter: String?) {
        switch status {
        case 200..<300:
            self = .delivered
        case 401, 403, 408, 429, 500..<600:
            self = .retryLater(after: retryAfter.flatMap(Int.init).map { .seconds(max(0, $0)) })
        default:
            self = .rejected
        }
    }
}

/// How much goes in one batch, how much is kept while sending is impossible, and how often to try.
///
/// The defaults are the ones the first-party receivers enforce: 100 events and 64 KB per request,
/// 500 kept on the device, and nothing sent within 60 seconds of the last try.
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
