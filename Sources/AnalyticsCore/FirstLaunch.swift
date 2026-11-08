import Foundation

/// Stamps the time of the first launch once, sends `first_open` once, and measures how long has
/// passed since.
///
/// **Which day** something that happened for the first time on this device happened on changes
/// how to read the first-run experience — doing it there and then, and remembering to come back
/// days later, call for fixing different things.
///
/// The state lives in `UserDefaults`. Losing it costs one fresh stamp and one more `first_open`,
/// and affects nothing the app does.
public enum FirstLaunch {

    private static let key = "analytics.firstLaunchAt"
    private static let openKey = "analytics.firstOpenSent"

    /// Call once on every launch, as early as measurement is set up. Stamps the first launch and,
    /// the first time, sends `first_open` (``CommonEvent/firstOpen(kind:)``).
    ///
    /// `kind` is ``FirstOpenKind/upgraded`` when the install was already in use before this
    /// measurement arrived — a launch stamp left by an earlier version, or `hasPriorData` — and
    /// ``FirstOpenKind/fresh`` otherwise. After the first call it does nothing but return `nil`.
    ///
    /// - Parameters:
    ///   - analytics: Where `first_open` goes
    ///   - hasPriorData: The app already holds data from an earlier version (a database, a
    ///     settings key). Pass it for apps that never stamped with `FirstLaunch` before
    ///   - defaults: Where the stamps are kept
    ///   - now: The current time, left injectable so tests can hold it still
    /// - Returns: The kind sent this time, or `nil` when `first_open` had been sent before
    @discardableResult
    public static func recordLaunch(
        sendingTo analytics: any AnalyticsClient,
        hasPriorData: Bool = false,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> FirstOpenKind? {
        let wasStamped = defaults.object(forKey: key) != nil
        if !wasStamped {
            defaults.set(now.timeIntervalSince1970, forKey: key)
        }
        guard !defaults.bool(forKey: openKey) else { return nil }
        defaults.set(true, forKey: openKey)
        let kind: FirstOpenKind = (wasStamped || hasPriorData) ? .upgraded : .fresh
        analytics.track(CommonEvent.firstOpen(kind: kind))
        return kind
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

    /// Clears the stamps, so the next launch is treated as the first, for tests and developer menus.
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: openKey)
    }
}
