import Foundation
import AnalyticsCore
import AnalyticsTesting
import Testing
@testable import AnalyticsSwiftUI

/// 画面の出来事を数え方に繋いでいる部分を固定する。
///
/// **事故が起きるのは定義ではなく繋ぎのほう。** `ImpressionTracker` の側は
/// 「50% を 1 秒」を正しく判定するが、`onAppear` を 2 箇所に書いた・`onDisappear` で
/// 待ちを止め忘れた・背面でも走り続けた、はどれもそこでは落ちない。
///
/// 待ちは注入してあるので、**実時間もシミュレータも要らない**。
@MainActor
@Suite("画面の出来事を数えに繋ぐ")
struct ImpressionSessionTests {

    /// 待たない `sleep`。時間の経過そのものはここでは関心ではない
    /// （「何秒か」は ImpressionTracker のテストが持っている）。
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
        // SwiftUI は View を作り直すことがあり、そのとき onAppear が再入する。
        // **これが「1 インストールで 2 回出ていた」事故の形。**
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
        session.disappeared()      // 待ちの途中で閉じた
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
        session.sceneChanged(isActive: false)   // 通知を開いた・アプリを切り替えた
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
        session.visibilityChanged(isVisible: false)   // 滞在しきる前に通り過ぎた
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
        // 一覧を上下に振ると可視・不可視が何度も来る。**そのたびに数えたら意味が変わる。**
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
