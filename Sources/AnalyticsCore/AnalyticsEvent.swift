/// One thing that happened in the app.
///
/// Conforming types are **generated per app** (`Scripts/analytics-gen.py` writes them out from
/// `analytics.yaml`). Writing one by hand is fine, but keep the shape the generator produces, so
/// that switching to generation later leaves the firing points untouched.
///
/// ## Names and parameters follow from the type
///
/// The library offers no way to send an event as a string. Misspellings, and events that are not
/// in the catalog, are held in a state that will not compile.
///
/// ## What may be carried
///
/// Enumerated cases and numbers only. **Never text a person wrote** — item names, display names,
/// email addresses, invite codes. There is no reason to aggregate them, and once sent they
/// cannot be taken back. Raw counts point at a single person at fine enough granularity, so put
/// them in bands with ``AnalyticsValue/bucket(_:edges:)``.
public protocol AnalyticsEvent: Sendable {

    /// Name handed to the destination.
    ///
    /// snake_case, prefixed with the area it belongs to (`ob_`, `paywall_`, and so on).
    var name: String { get }

    /// Values particular to this occurrence, keyed by the parameter name the destination sees.
    ///
    /// The default dedup key ignores them, so two occurrences that differ only in their
    /// parameters count as the same event.
    var parameters: [String: AnalyticsValue] { get }

    /// Which sort of occurrence this is. **The firing mechanism is chosen from it.**
    var kind: EventKind { get }

    /// The window over which repeats collapse into one. **Firing points never state this.**
    var dedup: DedupScope { get }
}

public extension AnalyticsEvent {

    /// Key under which "once ever" and "once per launch" are remembered.
    ///
    /// The default uses the name alone and ignores parameters: "responded to a notification for
    /// the first time" happens once whether the stage was `low` or `soon`, not once per stage.
    ///
    /// Override it in the conforming type only when each parameter value deserves its own count.
    var dedupKey: String { name }

    /// One-line rendering for logs and assertions.
    ///
    /// Takes the form `name key=value key=value`, with parameters sorted by key — dictionary
    /// order changes between runs, so an unsorted rendering could not serve as an expected value
    /// in a test.
    var debugLine: String {
        guard !parameters.isEmpty else { return name }
        let rendered = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: " ")
        return "\(name) \(rendered)"
    }
}

/// An attribute that stays attached to a person: not something that happened, but how things
/// currently stand.
///
/// Unlike an occurrence, setting the same value again leaves the result unchanged. Nothing has to
/// track the transition; set it again wherever the state is known.
public protocol AnalyticsUserProperty: Sendable {
    /// Name handed to the destination.
    var name: String { get }
    /// Value, restricted to an enumeration's raw value or a number already reduced to a band.
    var value: String { get }
}
