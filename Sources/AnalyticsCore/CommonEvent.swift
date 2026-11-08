/// The events from the common catalog (`Schema/common/common.yaml`) that this package sends by
/// itself.
///
/// The catalog marks them `sent_by: package`, and the generator leaves them out of each app's
/// event type, so there is one way to send each: ``FirstLaunch/recordLaunch(sendingTo:hasPriorData:defaults:now:)``
/// sends `first_open`, and ``AnalyticsInternalDevice/mark(sendingTo:defaults:)`` sends `internal_device`.
/// The names, parameters, and values here must match the catalog — the generator's tests check it.
public enum CommonEvent: AnalyticsEvent, Equatable {

    /// The first launch this install has measured. Where retention and cohorts start.
    case firstOpen(kind: FirstOpenKind)

    /// The device belongs to the people making the app. The receiver leaves this install out.
    case internalDevice

    public var name: String {
        switch self {
        case .firstOpen: return "first_open"
        case .internalDevice: return "internal_device"
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .firstOpen(kind): return ["kind": .text(kind.rawValue)]
        case .internalDevice: return [:]
        }
    }

    public var kind: EventKind { .outcome }

    public var dedup: DedupScope { .install }
}

/// Values of `first_open.kind`.
public enum FirstOpenKind: String, Sendable, CaseIterable {
    /// Newly installed.
    case fresh
    /// Updated from an earlier version, and launched for the first time with this measurement.
    case upgraded
}
