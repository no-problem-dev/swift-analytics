import Foundation
import AnalyticsCore
import AnalyticsTesting
import Testing
@testable import AnalyticsSwiftUI

/// Pins the part that wires a view's events onto the counting rule.
///
/// **Accidents happen in the wiring, not in the definition.** `ImpressionTracker` judges "50% for
/// one second" correctly, but `onAppear` written in two places, a wait left running by
/// `onDisappear`, and a timer that kept going in the background all get past it.
///
/// The waiting is injected, so **no real time and no simulator are needed**.
@MainActor
@Suite("画面の出来事を数えに繋ぐ")
struct ImpressionSessionTests {

    /// A `sleep` that does not wait. Time passing is not the concern here — how many seconds it
    /// takes belongs to the ImpressionTracker tests.
    private let noWait: @Sendable (TimeInterval) async -> Void = { _ in }

    private func make(_ recorder: RecordingAnalytics, dwell: TimeInterval = 1) -> ImpressionSession {
        ImpressionSession(
            event: Screen(),
            client: recorder,
            tracker: ImpressionTracker(dwell: dwell),
            sleep: noWait
        )
    }

    @Test("現れて滞在したら 1 回")
    func firesOnce() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        await session.settled()

        #expect(recorder.count(of: "screen_shown") == 1)
    }

    @Test("同じ露出で onAppear が二度来ても増えない")
    func doesNotDoubleFireOnReentry() async {
        // SwiftUI sometimes rebuilds a view, and onAppear comes again when it does.
        // **This is the shape of the "twice per install" accident.**
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        await session.settled()
        session.appeared()
        await session.settled()

        #expect(recorder.count(of: "screen_shown") == 1)
    }

    @Test("滞在しきる前に消えたら送らない")
    func doesNotFireWhenDismissedEarly() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        session.disappeared()      // closed partway through the wait
        await session.settled()

        #expect(recorder.names.isEmpty)
    }

    @Test("画面から外れて戻ってきたら、また数える")
    func firesAgainInANewEpisode() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        await session.settled()
        session.disappeared()
        session.appeared()
        await session.settled()

        #expect(recorder.count(of: "screen_shown") == 2)
    }

    @Test("背面に落ちている間は数えない")
    func doesNotFireInBackground() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        session.sceneChanged(isActive: false)   // opened a notification, or switched apps
        await session.settled()

        #expect(recorder.names.isEmpty)
    }

    @Test("前面に戻ったら数え直す")
    func firesAfterReturningToForeground() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.appeared()
        session.sceneChanged(isActive: false)
        await session.settled()
        session.sceneChanged(isActive: true)
        await session.settled()

        #expect(recorder.count(of: "screen_shown") == 1)
    }

    @Test("スクロールで流れていったら送らない")
    func doesNotFireWhenScrolledAway() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.visibilityChanged(isVisible: true)
        session.visibilityChanged(isVisible: false)   // scrolled past before the dwell elapsed
        await session.settled()

        #expect(recorder.names.isEmpty)
    }

    @Test("スクロールで見えて留まったら 1 回")
    func firesWhenScrolledIntoView() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.visibilityChanged(isVisible: true)
        await session.settled()

        #expect(recorder.count(of: "screen_shown") == 1)
    }

    @Test("同じ露出の中で見え隠れしても増えない")
    func doesNotFireAgainWithinTheSameEpisode() async {
        // Rocking a list up and down brings visible and hidden round again and again.
        // **Counting each time would change what the number means.**
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        session.visibilityChanged(isVisible: true)
        await session.settled()
        for _ in 0..<5 {
            session.visibilityChanged(isVisible: false)
            session.visibilityChanged(isVisible: true)
            await session.settled()
        }

        #expect(recorder.count(of: "screen_shown") == 1)
    }

    @Test("数えたことは外から見える")
    func exposesWhetherItFired() async {
        let recorder = RecordingAnalytics()
        let session = make(recorder)

        #expect(session.hasFired == false)
        session.appeared()
        await session.settled()
        #expect(session.hasFired == true)
    }
}

private struct Screen: AnalyticsEvent {
    var name: String { "screen_shown" }
    var parameters: [String: AnalyticsValue] { [:] }
    var kind: EventKind { .screen }
    var dedup: DedupScope { .episode }
}
