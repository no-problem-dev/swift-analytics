import Foundation
import os

/// How many times something has happened on this install, kept in `UserDefaults`.
///
/// For parameters such as `paywall_shown.nth` ("the how-many-th showing on this install"). The
/// catalog declares `nth` as a `bucket`, so the generated event turns the count into a band; this
/// only has to remember the count.
///
/// ```swift
/// // Where a showing begins — the same place the pw_id is made
/// let nth = OccurrenceCount.next("paywall_shown")
/// let event = AppEvent.paywallShown(source: .settings, pwId: pwID, nth: nth)
/// ```
///
/// **Count once per showing, not once per render.** A view body runs many times; calling
/// ``next(_:defaults:)`` there counts every render. Make the count where the showing starts and
/// hand the event to `trackImpression` from there.
///
/// It counts what happened, whether or not measurement is switched on, since the question is how
/// many times the person has seen it. ``resetAll(defaults:)`` belongs next to ``InstallID/reset(defaults:)``
/// when a person asks to be forgotten, so a new install ID does not start at the old count.
public enum OccurrenceCount {

    static let prefix = "analytics.count."

    /// Keeps two calls at once from both reading the same count.
    private static let lock = OSAllocatedUnfairLock()

    /// Adds one to the count for `key` and returns the new count: 1 the first time.
    ///
    /// - Parameter key: What is counted, usually the event's name (`"paywall_shown"`). Use a
    ///   longer key to count per place (`"paywall_shown.onboarding"`)
    @discardableResult
    public static func next(_ key: String, defaults: UserDefaults = .standard) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = max(0, defaults.integer(forKey: prefix + key)) + 1
        defaults.set(count, forKey: prefix + key)
        return count
    }

    /// The count for `key` so far, without adding to it. 0 when it has not happened.
    public static func current(_ key: String, defaults: UserDefaults = .standard) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return max(0, defaults.integer(forKey: prefix + key))
    }

    /// Forgets the count for `key`.
    public static func reset(_ key: String, defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: prefix + key)
    }

    /// Forgets every count this type has kept.
    public static func resetAll(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
