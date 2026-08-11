import AnalyticsCore
import Foundation

/// Turns a view's appearing, disappearing, returning to the foreground, and scrolling into view
/// into at most one send per exposure.
///
/// It feeds ``AnalyticsCore/ImpressionTracker``, owns the waiting, and sends once the wait comes
/// through intact.
///
/// ## Why it is lifted out of the ViewModifier
///
/// `ImpressionTracker` defines the counting itself, and tests pin it. **But accidents happen in
/// the wiring rather than in the definition** — `onAppear` written in two places, a wait left
/// running by an `onDisappear`, a timer that kept going into the background. Shut inside a
/// ViewModifier, none of those can be checked without drawing a screen.
///
/// Out here, these can be pinned **with no simulator and no waiting in real time**.
///
/// ```swift
/// let session = ImpressionSession(event: event, client: recorder, sleep: { _ in })
/// session.appeared()
/// await session.settled()
/// #expect(recorder.count(of: "paywall_shown") == 1)
///
/// session.appeared()           // a second onAppear in the same exposure (SwiftUI re-entry)
/// await session.settled()
/// #expect(recorder.count(of: "paywall_shown") == 1)   // unchanged
/// ```
///
/// The waiting is injectable: `Task.sleep` by default, and in tests a function that does not
/// wait at all.
@MainActor
public final class ImpressionSession {

    private var tracker: ImpressionTracker
    private let event: any AnalyticsEvent
    private let client: any AnalyticsClient
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - event: The occurrence to fire
    ///   - client: Where it is sent
    ///   - tracker: The counting rule; swap it to change the threshold or the dwell
    ///   - sleep: How to wait; tests pass a function that returns straight away
    public init(
        event: any AnalyticsEvent,
        client: any AnalyticsClient,
        tracker: ImpressionTracker = ImpressionTracker(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.event = event
        self.client = client
        self.tracker = tracker
        self.sleep = sleep
    }

    /// Reports that the screen, or the element, appeared, and starts the wait.
    ///
    /// **However many times it is called within one exposure, it counts once.** A repeated
    /// `onAppear` after the send has happened does nothing at all.
    public func appeared() {
        advance(tracker.visibility(1))
    }

    /// Reports that it left the screen: drops any wait in flight and ends the exposure.
    ///
    /// Whatever appears next counts again.
    public func disappeared() {
        cancel()
        tracker.endEpisode()
    }

    /// Reports that visibility changed inside a scrolling container.
    ///
    /// Becoming visible starts the wait; becoming hidden drops it, so an element scrolled past
    /// before the dwell elapses is never counted.
    public func visibilityChanged(isVisible: Bool) {
        advance(tracker.visibility(isVisible ? 1 : 0))
    }

    /// Reports a move between foreground and background.
    ///
    /// Going to the background drops the wait; coming back starts it again from the beginning,
    /// unless this exposure has already been counted.
    public func sceneChanged(isActive: Bool) {
        advance(tracker.foreground(isActive))
    }

    /// Waits for the work in flight to finish, for tests.
    ///
    /// Returns straight away when nothing is in flight, including right after the wait was
    /// dropped.
    public func settled() async {
        await pending?.value
    }

    /// Whether this exposure has already been counted.
    public var hasFired: Bool { tracker.hasFired }

    private func advance(_ action: ImpressionTracker.Action) {
        switch action {
        case .none:
            break
        case .cancelDwell:
            cancel()
        case let .startDwell(seconds):
            cancel()
            pending = Task { [weak self, sleep] in
                await sleep(seconds)
                guard !Task.isCancelled, let self else { return }
                // **Running out of time is not enough if the conditions have lapsed.**
                // The last gate keeping a missed cancellation from becoming a wrong count.
                guard self.tracker.dwellCompleted() else { return }
                self.client.track(self.event)
            }
        }
    }

    private func cancel() {
        pending?.cancel()
        pending = nil
    }
}
