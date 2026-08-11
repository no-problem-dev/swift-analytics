import AnalyticsCore

/// The smallest catalog that still covers the firings worth checking.
///
/// A real app's catalog is generated from `analytics.yaml`, but what is being checked here is
/// **the wiring rather than what is in the catalog**, so four hand-written cases are enough.
enum ProbeEvent: String, AnalyticsEvent, CaseIterable {
    /// A screen, measured with `trackScreen`.
    case screen = "screen"
    /// A screen inside a sheet.
    case sheet = "sheet"
    /// An element inside a scrolling container, measured with `trackImpression`.
    case row = "row"
    /// An element placed off screen. **If this reaches 1 or more, hazard H3 has been hit.**
    case offscreen = "offscreen"

    var name: String { rawValue }
    var parameters: [String: AnalyticsValue] { [:] }
    var kind: EventKind { self == .row || self == .offscreen ? .impression : .screen }
    var dedup: DedupScope { .always }
}
