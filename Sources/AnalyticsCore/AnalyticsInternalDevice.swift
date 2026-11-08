import Foundation

/// Remembers that this device belongs to the people making the app, and says so once.
///
/// The switch that turns it on (a hidden row in settings, a long press on the version number) is
/// the app's. This keeps the mark in `UserDefaults` and sends `internal_device` the first time it
/// is set; the receiver then leaves the install out of the numbers by its `install_id`.
///
/// There is no way to take the mark back on purpose: the receiver has already been told, and an
/// install that was internal once is not a clean sample afterwards either.
public enum AnalyticsInternalDevice {

    static let key = "analytics.internalDevice"

    /// Whether this device has been marked.
    public static func isInternal(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Marks the device as internal and sends `internal_device`, unless it was marked already.
    ///
    /// - Parameters:
    ///   - analytics: Where `internal_device` goes
    ///   - defaults: Where the mark is kept
    ///   - sendAgain: Send `internal_device` even though the device is marked. For apps whose
    ///     receiver keeps the mark by uid as well as by install: call it with `true` when the
    ///     signed-in person changes on a marked device
    /// - Returns: `true` when this call sent the event, `false` when it was marked before and
    ///   `sendAgain` was `false`
    @discardableResult
    public static func mark(
        sendingTo analytics: any AnalyticsClient,
        defaults: UserDefaults = .standard,
        sendAgain: Bool = false
    ) -> Bool {
        guard sendAgain || !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        analytics.track(CommonEvent.internalDevice)
        return true
    }

    /// Clears the mark, for tests.
    static func reset(defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

/// The name ``AnalyticsInternalDevice`` had in 0.3.0.
///
/// It was renamed because apps tend to have an `InternalDevice` of their own (the hidden switch, a
/// developer menu), and a file importing both modules could not name either without qualifying it.
/// This alias keeps 0.3.0 code compiling; it goes away in 0.4.0, and only then does the clash end.
@available(*, deprecated, renamed: "AnalyticsInternalDevice")
public typealias InternalDevice = AnalyticsInternalDevice
