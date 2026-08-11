/// A value that may be carried on an event parameter.
///
/// `Any` is not allowed, because destinations differ in what they accept and **quietly drop what
/// they cannot handle**. GA4, for instance, takes neither arrays nor dictionaries: the send looks
/// successful and the value never reaches the dashboard. Narrowing the type here makes the
/// compiler stop it first.
///
/// Only `String`, `Int`, `Double`, and `Bool` are representable, through the four cases below.
/// Anything else — a date, an array, a model object — has no case to go into and has to be
/// reduced at the call site, most often to a raw value or to a band.
public enum AnalyticsValue: Sendable, Equatable {

    /// An enumeration's raw value. **Never text a person wrote** (item name, display name, free
    /// input).
    case text(String)

    /// A whole number, such as a number of items or a number of days.
    case count(Int)

    /// A fractional number, such as a ratio or a duration in seconds.
    case number(Double)

    /// A boolean, rendered as the words `true` and `false`.
    ///
    /// Destinations that want it as a number get it that way from their own adapter; nothing in
    /// this package converts it.
    case flag(Bool)

    /// Reduces a number to a labelled band.
    ///
    /// A raw count points at a single person at fine enough granularity (there is only one person
    /// "with 137 items"). Aggregation usually needs the magnitude rather than the number, so pick
    /// boundaries and report the band.
    ///
    /// ```swift
    /// AnalyticsValue.bucket(0, edges: [1, 6, 16])   // "0"
    /// AnalyticsValue.bucket(3, edges: [1, 6, 16])   // "1_5"
    /// AnalyticsValue.bucket(99, edges: [1, 6, 16])  // "16_plus"
    /// ```
    ///
    /// Anything below the lowest edge is labelled with that edge minus one, whatever the value
    /// actually is, so the label of a band never carries the number it was meant to hide. Passing
    /// no edges at all puts every value in a band labelled `"0"`.
    ///
    /// - Parameters:
    ///   - value: The number to reduce
    ///   - edges: Lower bounds of the bands. Sorted internally, so the order they arrive in does
    ///     not change the result
    public static func bucket(_ value: Int, edges: [Int]) -> AnalyticsValue {
        let sorted = edges.sorted()
        guard let first = sorted.first, value >= first else {
            return .text(String(sorted.first.map { $0 - 1 } ?? 0))
        }
        for (index, lower) in sorted.enumerated() {
            let upper = index + 1 < sorted.count ? sorted[index + 1] : nil
            guard let upper else { return .text("\(lower)_plus") }
            if value < upper { return .text("\(lower)_\(upper - 1)") }
        }
        return .text("\(first)_plus")
    }
}

extension AnalyticsValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .text(value): return value
        case let .count(value): return String(value)
        case let .number(value): return String(value)
        case let .flag(value): return value ? "true" : "false"
        }
    }
}
