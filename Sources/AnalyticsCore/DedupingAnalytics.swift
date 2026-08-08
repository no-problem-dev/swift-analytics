import Foundation

/// カタログの ``DedupScope`` を実施する層。**発火点から「もう撃ったか」の判断を取り上げる。**
///
/// これが無いと、発火点の側に `guard alreadyFired == false else { return }` を書くことになる。
/// 撃つ場所が 2 つある出来事では同じ判定が 2 箇所に散り、片方だけ直る形になる。
/// 数え方はカタログが持っているのだから、実施も 1 箇所に畳む。
///
/// ```swift
/// let analytics = DedupingAnalytics(MultiplexAnalytics([ConsoleAnalytics(), firebase]))
/// ```
///
/// ## 範囲ごとの扱い
///
/// | 範囲 | ここでの扱い |
/// |---|---|
/// | ``DedupScope/install`` | `UserDefaults` の印。消えても最悪もう一度数えるだけ |
/// | ``DedupScope/session`` | このオブジェクトが生きている間の記憶 |
/// | ``DedupScope/episode`` | **何もしない。**露出の一区切りは画面の概念なので ``ImpressionTracker`` が持つ |
/// | ``DedupScope/always`` | 素通し |
///
/// 属性（``AnalyticsUserProperty``）は間引かない。属性は「いまの状態」なので、
/// 同じ値を何度置いても結果が変わらず、間引くと復元時に古い値が残る。
public final class DedupingAnalytics: AnalyticsClient, @unchecked Sendable {

    private let wrapped: any AnalyticsClient
    private let defaults: UserDefaults

    /// `firedThisSession` を守る。`Sendable` を手で請け負っているのはこの 1 つの可変状態のためで、
    /// 触る経路は ``track(_:)`` しかない。
    private let lock = NSLock()
    private var firedThisSession: Set<String> = []

    /// - Parameters:
    ///   - wrapped: 実際に送る先
    ///   - defaults: ``DedupScope/install`` の印を置く場所。テストでは専用のスイートを渡す
    public init(_ wrapped: any AnalyticsClient, defaults: UserDefaults = .standard) {
        self.wrapped = wrapped
        self.defaults = defaults
    }

    public func track(_ event: any AnalyticsEvent) {
        guard shouldSend(event) else { return }
        wrapped.track(event)
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        wrapped.setUserProperty(property)
    }

    private func shouldSend(_ event: any AnalyticsEvent) -> Bool {
        switch event.dedup {
        case .always, .episode:
            return true
        case .session:
            lock.lock()
            defer { lock.unlock() }
            return firedThisSession.insert(event.dedupKey).inserted
        case .install:
            let key = Self.installKey(for: event.dedupKey)
            lock.lock()
            defer { lock.unlock() }
            guard !defaults.bool(forKey: key) else { return false }
            defaults.set(true, forKey: key)
            return true
        }
    }

    static func installKey(for dedupKey: String) -> String {
        "analytics.fired.\(dedupKey)"
    }
}
