import Foundation

/// Remembers that this device belongs to the people making the app, and says so once.
///
/// The switch that turns it on (a hidden row in settings, a long press on the version number) is
/// the app's. This keeps the mark in `UserDefaults` and sends `internal_device` the first time it
/// is set; the receiver then leaves the install out of the numbers by its `install_id`.
///
/// There is no way to take the mark back on purpose: the receiver has already been told, and an
/// install that was internal once is not a clean sample afterwards either.
public enum InternalDevice {

    static let key = "analytics.internalDevice"

    /// Whether this device has been marked.
    public static func isInternal(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Marks the device as internal and sends `internal_device`, unless it was marked already.
    ///
    /// - Returns: `true` when this call marked it (and sent the event), `false` when it was
    ///   marked before
    @discardableResult
    public static func mark(sendingTo analytics: any AnalyticsClient, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        analytics.track(CommonEvent.internalDevice)
        return true
    }

    /// Clears the mark, for tests.
    static func reset(defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
