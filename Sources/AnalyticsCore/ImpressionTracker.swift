import Foundation

/// 「見えた」の定義を 1 箇所に閉じる状態機械。
///
/// ## なぜ `onAppear` では足りないのか
///
/// `onAppear` は「人が見た」を意味しない。View の同一性が変われば再入し、変わらなければ
/// 二度と来ず、0.05 秒よぎっただけでも来る。どれも「何回見たか」とは関係が無い。
/// 素朴に `@State` で 1 回に絞っても、絞られるのは View の一生であって、人の閲覧ではない。
///
/// ## 採る定義
///
/// 広告計測で決着している基準（MRC のモバイルアプリ内表示計測ガイドライン）に合わせる。
///
/// > **面積の 50% 以上が、連続して 1.0 秒以上見えていたら 1 回。**
///
/// 「業界標準だから」ではなく、**時間を入れないと定義が閉じないから**。面積だけでは
/// 「一瞬映った」を排除できず、`onAppear` の穴がそのまま残る。ペイウォールを読んだ人と、
/// ペイウォールが一瞬映った人が同じ数字になる。
///
/// ## 時計を持たない
///
/// 「何秒待て」を返すだけで、待つのは呼ぶ側の仕事にしてある。おかげで
/// **シミュレータも実時間の待ちもなしに**、次のような性質をそのまま固定できる。
///
/// ```swift
/// var tracker = ImpressionTracker()
/// #expect(tracker.visibility(1.0) == .startDwell(1.0))
/// #expect(tracker.visibility(0.0) == .cancelDwell)
/// #expect(tracker.dwellCompleted() == false)   // 0.9 秒で消えたら数えない
/// ```
public struct ImpressionTracker: Sendable, Equatable {

    /// 呼ぶ側にしてほしいこと。
    public enum Action: Sendable, Equatable {

        /// この秒数だけ見え続けたら ``ImpressionTracker/dwellCompleted()`` を呼ぶ。
        case startDwell(TimeInterval)

        /// 待つのをやめる（見えなくなった、または背面に落ちた）。
        case cancelDwell

        /// 何もしない。
        case none
    }

    /// 可視とみなす面積の割合。
    public let threshold: Double

    /// 連続して見えている必要のある秒数。
    public let dwell: TimeInterval

    private var isVisible = false
    private var isForeground = true

    /// この露出の一区切りで、もう数えたか。
    public private(set) var hasFired = false

    /// - Parameters:
    ///   - threshold: 可視とみなす面積の割合。既定は 0.5（MRC 基準）
    ///   - dwell: 連続して見えている必要のある秒数。既定は 1.0（MRC 基準の表示広告）
    public init(threshold: Double = 0.5, dwell: TimeInterval = 1.0) {
        self.threshold = threshold
        self.dwell = dwell
    }

    /// 見えている割合が変わった。
    ///
    /// スクロールの可視通知や、`onAppear` / `onDisappear` から流す。
    /// - Parameter fraction: 0.0（まったく見えない）〜 1.0（全部見えている）
    public mutating func visibility(_ fraction: Double) -> Action {
        isVisible = fraction >= threshold
        return settle()
    }

    /// 前面／背面が変わった。
    ///
    /// **背面では、画面に出ていても人は見ていない。** 通知を開いた・アプリを切り替えた間に
    /// 数え続けると、滞在時間の条件が意味を失う。
    public mutating func foreground(_ active: Bool) -> Action {
        isForeground = active
        return settle()
    }

    /// 露出の一区切りが終わった（画面から外れた）。次に見えたら、また数える。
    public mutating func endEpisode() {
        isVisible = false
        hasFired = false
    }

    /// 待ち時間が満了した。**`true` のときだけ数える。**
    ///
    /// 満了までに見えなくなっていれば `false` を返す。待っている間に条件が崩れていないかは、
    /// タイマーの取り消しではなくここで判定する —— 取り消し漏れを数え違いに変えないため。
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
