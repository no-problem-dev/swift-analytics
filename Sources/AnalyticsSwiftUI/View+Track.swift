import AnalyticsCore
import SwiftUI

public extension View {

    /// **Counts arriving at a screen.**
    ///
    /// Once the view has appeared and stayed for `dwell` seconds with the app in the foreground,
    /// that counts once. Leaving the screen and coming back counts again, and time spent in the
    /// background does not count.
    ///
    /// Dropping the display that merely flashed past is the point — the person who read the
    /// paywall and the person it flashed past should not land on the same number.
    ///
    /// ```swift
    /// PaywallView(...)
    ///     .trackScreen(.paywallShown(source: .settings))
    /// ```
    ///
    /// - Parameters:
    ///   - event: The occurrence to fire; ``AnalyticsCore/EventKind/screen`` is what this is for
    ///   - dwell: Seconds it has to stay before it counts
    ///
    /// - Note: There is no area threshold here on purpose. A whole screen has appeared or it has
    ///   not — there is no fraction to compare — so a threshold could only be inert or, above 1.0,
    ///   silently stop the event being counted at all.
    func trackScreen(
        _ event: any AnalyticsEvent,
        dwell: TimeInterval = 1.0
    ) -> some View {
        modifier(TrackScreenModifier(event: event, dwell: dwell))
    }

    /// **Counts an element inside a scrolling container actually coming into view.**
    ///
    /// The judgement rides on `onScrollVisibilityChange`, whose threshold defaults to 0.5 and so
    /// lines up with the definition taken from advertising measurement (50% of the area). Once the
    /// element has been visible for `dwell` seconds, that counts once; scrolling it away and back
    /// counts again.
    ///
    /// - Important: **It does not fire outside a scrolling container.** To count a screen itself,
    ///   use ``SwiftUICore/View/trackScreen(_:dwell:)``. It deliberately does not fall back
    ///   to `onAppear` so as to work outside one — in a lazily built list, `onAppear` arrives for
    ///   rows that are off screen, which quietly mixes "counted as seen without being visible"
    ///   into the numbers.
    ///
    /// - Parameters:
    ///   - event: The occurrence to fire; ``AnalyticsCore/EventKind/impression`` is what this is
    ///     for
    ///   - threshold: Fraction of the element's area that has to be on screen. Unlike on a whole
    ///     screen, this one is measured
    ///   - dwell: Seconds it has to stay visible before it counts
    @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func trackImpression(
        _ event: any AnalyticsEvent,
        threshold: Double = 0.5,
        dwell: TimeInterval = 1.0
    ) -> some View {
        modifier(TrackImpressionModifier(event: event, threshold: threshold, dwell: dwell))
    }
}

// MARK: - Implementation
//
// **Both do nothing but feed ``ImpressionSession``.**
// Neither the judgement nor the waiting lives here, so the tests can be written on the session
// side (a ViewModifier cannot be run without drawing a screen, and a branch placed in one becomes
// impossible to check).

private struct TrackScreenModifier: ViewModifier {

    @Environment(\.analytics) private var analytics
    @Environment(\.scenePhase) private var scenePhase

    let event: any AnalyticsEvent
    let dwell: TimeInterval

    @State private var session: ImpressionSession?

    func body(content: Content) -> some View {
        content
            .onAppear {
                let session = session ?? makeSession()
                self.session = session
                session.appeared()
            }
            .onDisappear { session?.disappeared() }
            // Count again on the way back to the foreground. **Someone returning from a
            // notification is looking at that screen.**
            .onChange(of: scenePhase) { _, phase in
                session?.sceneChanged(isActive: phase == .active)
            }
    }

    private func makeSession() -> ImpressionSession {
        ImpressionSession(event: event, client: analytics, tracker: ImpressionTracker(dwell: dwell))
    }
}

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private struct TrackImpressionModifier: ViewModifier {

    @Environment(\.analytics) private var analytics
    @Environment(\.scenePhase) private var scenePhase

    let event: any AnalyticsEvent
    let threshold: Double
    let dwell: TimeInterval

    @State private var session: ImpressionSession?

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: threshold) { visible in
                let session = session ?? makeSession()
                self.session = session
                session.visibilityChanged(isVisible: visible)
            }
            .onDisappear { session?.disappeared() }
            .onChange(of: scenePhase) { _, phase in
                session?.sceneChanged(isActive: phase == .active)
            }
    }

    // `threshold` goes to `onScrollVisibilityChange` and stops there. It is the one place the area
    // is actually compared, and applying it a second time inside the tracker would only add a
    // second way for a value above 1.0 to zero the event.
    private func makeSession() -> ImpressionSession {
        ImpressionSession(event: event, client: analytics, tracker: ImpressionTracker(dwell: dwell))
    }
}
