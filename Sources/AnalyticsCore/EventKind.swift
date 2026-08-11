/// Which sort of thing an occurrence is.
///
/// The distinction long carried informally as "tap logs" and "view logs", turned into vocabulary.
/// Fixing the sort fixes the default counting rule, which leaves the firing point with nothing to
/// state but where.
///
/// ## Facts are absent on purpose
///
/// **Domain facts are not sent from the client** — bought, household created, notification sent.
/// The fact is already persisted on the server and that is the authoritative copy, so sending the
/// same thing as an event guarantees a discrepancy, with no way left to decide which side is
/// right (anything recorded offline and synced later has a send time that differs from the time
/// it happened).
///
/// Count those with SQL over the server's data. That discipline is what **removes any need to
/// thread measurement through the use-case layer** — measurement never takes up residence in the
/// architecture.
public enum EventKind: String, Sendable, CaseIterable {

    /// Arrived at a screen.
    case screen

    /// An element in a list actually became visible. **Only meaningful inside a scrollable
    /// container.**
    case impression

    /// Pressed, chose, or typed.
    case interaction

    /// Finished, failed, or gave up.
    case outcome
}

/// The window over which repeats of one occurrence collapse into a single count.
///
/// ## Why it belongs in the vocabulary
///
/// When the counting rule is written down nowhere, **nobody can call a second firing point a
/// mistake**. In one app the onboarding-start event was fired from both the consent screen and
/// the flow itself, and came out twice per install. The completion rate looked like half of what
/// it was, and neither the types, nor the tests, nor the dashboard could say anything was wrong.
///
/// With "once per install" in the catalog, the second firing point fails the check.
///
/// ## Every case is a send-layer window
///
/// Every case here narrows repeats at the point the event is sent, and ``DedupingAnalytics``
/// enforces all of them. **Per-exposure counting is deliberately absent**: an exposure is a
/// view-level span the send path cannot see, and the send path keys on
/// ``AnalyticsEvent/dedupKey``, which ignores parameters — so twenty rows of a list firing the same
/// impression would collapse into one. That rule belongs to, and is enforced by,
/// ``ImpressionTracker`` and the kind of event it is (``EventKind/screen``,
/// ``EventKind/impression``), not to a scope declared here.
public enum DedupScope: String, Sendable, CaseIterable {

    /// Once while the app is running.
    ///
    /// The window is the lifetime of the ``DedupingAnalytics`` instance, so relaunching the app
    /// counts again.
    case session

    /// Once ever on this device.
    ///
    /// Whether the first-run experience worked can only be told from the first run — a second
    /// "bought" says nothing about it. The flag lives in `UserDefaults`, so it survives relaunches
    /// and clears only when the app is deleted or that store is wiped.
    case install

    /// Every time. For an interaction, the number of times it happened is the point.
    case always
}
