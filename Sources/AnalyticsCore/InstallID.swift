import Foundation
import os

/// The ID of this install: a UUID made on first use and kept in `UserDefaults`.
///
/// It goes into every batch as `install_id` (`Schema/common/ENVELOPE.md`), and is what the
/// receiver groups an install's events by. Deleting and reinstalling the app makes a new one, and
/// so does ``reset(defaults:)`` — use that when a person asks for their data to be forgotten.
///
/// It identifies an install, not a person. Never send it anywhere that ties it to a name or an
/// email address.
public enum InstallID {

    static let key = "analytics.installID"

    /// Keeps two first calls from making two different IDs.
    private static let lock = OSAllocatedUnfairLock()

    /// The stored ID, made and stored first if there is none (or what is stored is not a UUID).
    ///
    /// Lower-case, as `UUID().uuidString.lowercased()` writes it.
    public static func current(defaults: UserDefaults = .standard) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let stored = defaults.string(forKey: key), UUID(uuidString: stored) != nil {
            return stored
        }
        let made = UUID().uuidString.lowercased()
        defaults.set(made, forKey: key)
        return made
    }

    /// Takes over the ID an earlier version kept somewhere else, so the install stays the same install.
    ///
    /// For moving onto this package: an app that already sent an install ID (and tied it to a
    /// subscription service or its own receiver) passes it here once at launch, before anything
    /// reads ``current(defaults:)``. After that, delete the old copy, so that ``reset(defaults:)``
    /// cannot be undone by adopting it again.
    ///
    /// It does nothing when an ID is already stored — that install already has one, and replacing
    /// it would split it in two — and nothing when `id` is not a UUID, which is what the envelope
    /// carries.
    ///
    /// - Returns: `true` when `id` was stored, lower-cased
    @discardableResult
    public static func adopt(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard UUID(uuidString: id) != nil else { return false }
        if let stored = defaults.string(forKey: key), UUID(uuidString: stored) != nil {
            return false
        }
        defaults.set(id.lowercased(), forKey: key)
        return true
    }

    /// Forgets the ID, so the next ``current(defaults:)`` makes a new one.
    public static func reset(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
