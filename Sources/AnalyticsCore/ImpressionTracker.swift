import Foundation

/// A state machine that shuts the definition of "was seen" inside one place.
///
/// ## Why `onAppear` is not enough
///
/// `onAppear` does not mean a person saw anything. It comes again when the view's identity
/// changes, never comes again when it does not, and arrives for something that flashed past in
/// 0.05 seconds. None of that has anything to do with how many times something was seen. Naively
/// narrowing it to once with `@State` narrows to the life of a view, not to a person's viewing.
///
/// ## The definition taken
///
/// The one settled in advertising measurement: the MRC's mobile in-app viewable impression
/// guidelines.
///
/// > **At least 50% of the area, visible continuously for at least 1.0 second, counts once.**
///
/// Not because it is the industry standard, but because **the definition does not close without a
/// duration in it**. Area alone cannot rule out the momentary flash, which leaves the `onAppear`
/// hole exactly where it was: the person who read the paywall and the person it flashed past land
/// on the same number.
///
/// ## It holds no clock
///
/// It only answers how many seconds to wait; waiting is the caller's job. That is what lets these
/// properties be pinned **with no simulator and no waiting in real time**.
///
/// ```swift
/// var tracker = ImpressionTracker()
/// #expect(tracker.visibility(1.0) == .startDwell(1.0))
/// #expect(tracker.visibility(0.0) == .cancelDwell)
/// #expect(tracker.dwellCompleted() == false)   // gone at 0.9 seconds, so not counted
/// ```
public struct ImpressionTracker: Sendable, Equatable {

    /// What the caller is being asked to do.
    public enum Action: Sendable, Equatable {

        /// Wait this many seconds, and if it stays visible throughout, call
        /// ``ImpressionTracker/dwellCompleted()``.
        case startDwell(TimeInterval)

        /// Stop waiting: it went out of view, or the app dropped into the background.
        case cancelDwell

        /// Nothing to do — it has already been counted in this exposure.
        case none
    }

    /// Fraction of the area that has to be visible before it counts as visible at all.
    public let threshold: Double

    /// Seconds it has to stay continuously visible before it counts.
    public let dwell: TimeInterval

    private var isVisible = false
    private var isForeground = true

    /// Whether this exposure has already been counted; cleared by ``endEpisode()``.
    public private(set) var hasFired = false

    /// - Parameters:
    ///   - threshold: Fraction of the area treated as visible. 0.5 is the MRC figure
    ///   - dwell: Seconds it has to stay visible without a break. 1.0 is the MRC figure for
    ///     display advertising
    public init(threshold: Double = 0.5, dwell: TimeInterval = 1.0) {
        self.threshold = threshold
        self.dwell = dwell
    }

    /// Takes a new visible fraction and answers what to do about it.
    ///
    /// Feed it from a scroll visibility notification, or from `onAppear` and `onDisappear`. It
    /// asks for a wait as soon as the fraction reaches the threshold, and asks for that wait to be
    /// dropped as soon as it falls below.
    ///
    /// - Parameter fraction: 0.0 for not visible at all, through 1.0 for entirely visible
    public mutating func visibility(_ fraction: Double) -> Action {
        visible(fraction >= threshold)
    }

    /// Takes a visibility that has already been decided, and answers what to do about it.
    ///
    /// For callers holding a yes/no rather than an area: `onAppear` on a whole screen, which has no
    /// fraction to measure, and `onScrollVisibilityChange(threshold:)`, which applied its own
    /// threshold before calling. **Passing such an answer through ``visibility(_:)`` as the
    /// fraction `1` would put it back under ``threshold``**, where a threshold above 1.0 turns
    /// every yes into a no and the counting stops without a word.
    public mutating func visible(_ isVisible: Bool) -> Action {
        self.isVisible = isVisible
        return settle()
    }

    /// Takes a move between foreground and background, and answers what to do about it.
    ///
    /// **In the background, nobody is looking, whatever is on screen.** Counting on through the
    /// time spent in an opened notification or another app would empty the dwell condition of its
    /// meaning. Coming back to the foreground asks for the wait to start over from the beginning.
    public mutating func foreground(_ active: Bool) -> Action {
        isForeground = active
        return settle()
    }

    /// Ends this exposure, so that becoming visible again counts again.
    ///
    /// Marks it as no longer visible and clears ``hasFired``. Any wait already in flight stays the
    /// caller's to cancel.
    public mutating func endEpisode() {
        isVisible = false
        hasFired = false
    }

    /// Reports that the wait ran out, and answers whether this one counts.
    ///
    /// True at most once per exposure, and only while the element is still visible and the app is
    /// still in the foreground. Whether the conditions held throughout the wait is decided here
    /// rather than by cancelling the timer — so that a cancellation missed on the way never turns
    /// into a wrong count.
    public mutating func dwellCompleted() -> Bool {
        guard isCountable, !hasFired else { return false }
        hasFired = true
        return true
    }

    private var isCountable: Bool { isVisible && isForeground }

    private mutating func settle() -> Action {
        guard isCountable else { return .cancelDwell }
        guard !hasFired else { return .none }
        return .startDwell(dwell)
    }
}
