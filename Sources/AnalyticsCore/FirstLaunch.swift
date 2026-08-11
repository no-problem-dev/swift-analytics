import Foundation

/// Stamps the time of the first launch once, and measures how long has passed since.
///
/// **Which day** something that happened for the first time on this device happened on changes
/// how to read the first-run experience — doing it there and then, and remembering to come back
/// days later, call for fixing different things.
///
/// The state lives in `UserDefaults`. Losing it costs one fresh stamp and affects nothing the app
/// does.
public enum FirstLaunch {

    private static let key = "analytics.firstLaunchAt"

    /// Stamps the time of the first launch, unless one is already stored.
    ///
    /// **Safe to call on every launch** — after the first, it does nothing at all.
    ///
    /// - Parameters:
    ///   - defaults: Where the stamp is kept
    ///   - now: The current time, left injectable so tests can hold it still
    public static func markIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: key)
    }

    /// Whole days elapsed since the first launch, counting the first 24 hours as day 0.
    ///
    /// With nothing stamped it answers 0, treating an unknown device as being on its first day,
    /// and it never goes below 0 even if the clock moves backwards.
    public static func daysSince(defaults: UserDefaults = .standard, now: Date = Date()) -> Int {
        let stored = defaults.double(forKey: key)
        guard stored > 0 else { return 0 }
        let elapsed = now.timeIntervalSince1970 - stored
        return max(0, Int(elapsed / 86_400))
    }

    /// Clears the stamp, so the next launch is treated as the first, for tests and developer menus.
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
