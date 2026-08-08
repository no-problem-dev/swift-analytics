import AnalyticsCore
import Foundation

/// 画面の出来事（現れた・消えた・前面に戻った・スクロールで見えた）を
/// ``AnalyticsCore/ImpressionTracker`` に流し、待ってから送るところまでを持つ。
///
/// ## なぜ ViewModifier から切り出すのか
///
/// `ImpressionTracker` は数え方そのものを定義していて、テストで固定してある。
/// **けれど事故が起きるのはたいてい定義ではなく「繋ぎ」のほう** ——
/// `onAppear` を 2 箇所に書いた、`onDisappear` で待ちを止め忘れた、背面に落ちても走り続けた。
/// ViewModifier の中に閉じ込めると、それらは画面を描かないと確かめられなくなる。
///
/// ここに出しておけば、**シミュレータも実時間の待ちもなしに**次のことが固定できる。
///
/// ```swift
/// let session = ImpressionSession(event: event, client: recorder, sleep: { _ in })
/// session.appeared()
/// await session.settled()
/// #expect(recorder.count(of: "paywall_shown") == 1)
///
/// session.appeared()           // 同じ露出で二度目の onAppear（SwiftUI の再入）
/// await session.settled()
/// #expect(recorder.count(of: "paywall_shown") == 1)   // 増えない
/// ```
///
/// 待ちは注入できる。既定は `Task.sleep`、テストでは「待たない」関数を渡す。
@MainActor
public final class ImpressionSession {

    private var tracker: ImpressionTracker
    private let event: any AnalyticsEvent
    private let client: any AnalyticsClient
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - event: 撃つ出来事
    ///   - client: 送信口
    ///   - tracker: 数え方。しきい値と滞在時間を変えたいときに差し替える
    ///   - sleep: 待ち方。テストでは待たない関数を渡す
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

    /// 画面（または要素）が現れた。**同じ露出の中で何度呼ばれても 1 回しか数えない。**
    public func appeared() {
        advance(tracker.visibility(1))
    }

    /// 画面から外れた。待ちを止め、次に現れたらまた数える。
    public func disappeared() {
        cancel()
        tracker.endEpisode()
    }

    /// スクロールの中で見え方が変わった。
    public func visibilityChanged(isVisible: Bool) {
        advance(tracker.visibility(isVisible ? 1 : 0))
    }

    /// 前面／背面が変わった。
    public func sceneChanged(isActive: Bool) {
        advance(tracker.foreground(isActive))
    }

    /// 待っている処理が終わるまで待つ（テスト用）。
    public func settled() async {
        await pending?.value
    }

    /// この露出で既に数えたか。
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
                // **満了しても、条件が崩れていれば数えない。**
                // 取り消し漏れを数え違いに変えないための最後の関所。
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
