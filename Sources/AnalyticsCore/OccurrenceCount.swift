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

    /// Where ``adopt(_:count:defaults:)`` notes that it has run. Outside `prefix`, so
    /// ``resetAll(defaults:)`` does not let an old count come back in.
    static let adoptedPrefix = "analytics.countAdopted."

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

    /// Carries over a count the app kept itself before it used this type, once per `key`.
    ///
    /// Call it at launch, before the first ``next(_:defaults:)``, with the count from the app's own
    /// key (`funnel_paywall_display_count`). The count is added to what is here, and the call is
    /// noted, so later calls do nothing — the old key can stay where it is. The note survives
    /// ``reset(_:defaults:)`` and ``resetAll(defaults:)``, so a person who asked to be forgotten
    /// does not get the old count back on the next launch.
    ///
    /// ```swift
    /// OccurrenceCount.adopt("paywall_shown", count: UserDefaults.standard.integer(forKey: "funnel_paywall_display_count"))
    /// ```
    ///
    /// - Parameters:
    ///   - key: What is counted, the same key given to ``next(_:defaults:)``
    ///   - count: The count the earlier version kept. 0 or less adds nothing, and still counts as
    ///     the one carry-over
    /// - Returns: The count for `key` after the call
    @discardableResult
    public static func adopt(_ key: String, count: Int, defaults: UserDefaults = .standard) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = max(0, defaults.integer(forKey: prefix + key))
        guard !defaults.bool(forKey: adoptedPrefix + key) else { return current }
        defaults.set(true, forKey: adoptedPrefix + key)
        let total = current + max(0, count)
        defaults.set(total, forKey: prefix + key)
        return total
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
