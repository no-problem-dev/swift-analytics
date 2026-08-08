import AnalyticsCore
import SwiftUI

public extension View {

    /// **画面に着いたことを数える。**
    ///
    /// 面積の 50% 以上が 1 秒以上連続して見えたら 1 回（``AnalyticsCore/ImpressionTracker``）。
    /// 画面から外れて戻ればまた数え、背面に落ちている間は数えない。
    ///
    /// 一瞬よぎっただけの表示を落とすのが要点 —— ペイウォールを読んだ人と、
    /// ペイウォールが一瞬映った人を同じ数字にしない。
    ///
    /// ```swift
    /// PaywallView(...)
    ///     .trackScreen(.paywallShown(source: .settings))
    /// ```
    ///
    /// - Parameters:
    ///   - event: 撃つ出来事。``AnalyticsCore/EventKind/screen`` を想定している
    ///   - threshold: 可視とみなす割合。画面では通常そのままでよい
    ///   - dwell: 連続して見えている必要のある秒数
    func trackScreen(
        _ event: any AnalyticsEvent,
        threshold: Double = 0.5,
        dwell: TimeInterval = 1.0
    ) -> some View {
        modifier(TrackScreenModifier(event: event, threshold: threshold, dwell: dwell))
    }

    /// **スクロールできる器の中で、要素が実際に見えたことを数える。**
    ///
    /// 判定は `onScrollVisibilityChange` に載せる。しきい値の既定 0.5 が、
    /// そのまま採った定義（面積の 50%）と一致する。
    ///
    /// - Important: **スクロールできる器の外では発火しない。** 画面そのものを数えたいなら
    ///   ``SwiftUI/View/trackScreen(_:threshold:dwell:)`` を使う。
    ///   器の外でも動くように `onAppear` へ落とす作りにはしていない ——
    ///   遅延生成の一覧では画面外の行にも `onAppear` が来るので、
    ///   「見えていないのに見えたことになる」数字が静かに混ざる。
    @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func trackImpression(
        _ event: any AnalyticsEvent,
        threshold: Double = 0.5,
        dwell: TimeInterval = 1.0
    ) -> some View {
        modifier(TrackImpressionModifier(event: event, threshold: threshold, dwell: dwell))
    }
}

// MARK: - 実装
//
// **どちらも ``ImpressionSession`` へ流すだけにしてある。**
// 判断も待ちもここには無いので、テストは Session の側に書ける
// （ViewModifier は画面を描かないと動かせず、そこに条件分岐を置くと確かめられなくなる）。

private struct TrackScreenModifier: ViewModifier {

    @Environment(\.analytics) private var analytics
    @Environment(\.scenePhase) private var scenePhase

    let event: any AnalyticsEvent
    let threshold: Double
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
            // 前面に戻ったら数え直す。**通知から戻ってきた人は、その画面を見ている。**
            .onChange(of: scenePhase) { _, phase in
                session?.sceneChanged(isActive: phase == .active)
            }
    }

    private func makeSession() -> ImpressionSession {
        ImpressionSession(
            event: event,
            client: analytics,
            tracker: ImpressionTracker(threshold: threshold, dwell: dwell)
        )
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

    private func makeSession() -> ImpressionSession {
        ImpressionSession(
            event: event,
            client: analytics,
            tracker: ImpressionTracker(threshold: threshold, dwell: dwell)
        )
    }
}
