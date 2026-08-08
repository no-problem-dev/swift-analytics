import AnalyticsCore
import Foundation

/// 撃たれた計測を覚えるだけの送信口。
///
/// 「この操作でこの出来事が、**この順で、この回数**出る」をテストに固定するために使う。
/// 回数まで見るのが要点 —— 計測の事故はたいてい「出ない」ではなく「出すぎる」で、
/// 出すぎは名前を数えるだけの検査では見えない。
///
/// ```swift
/// let analytics = RecordingAnalytics()
/// // ... 操作 ...
/// #expect(analytics.names == ["tutorial_begin", "tutorial_complete"])
/// ```
public final class RecordingAnalytics: AnalyticsClient, @unchecked Sendable {

    /// 記録を守る。`Sendable` を手で請け負っているのはこの 2 つの可変状態のためで、
    /// 触る経路はこのファイルの中しかない。
    private let lock = NSLock()
    private var storedEvents: [any AnalyticsEvent] = []
    private var storedProperties: [any AnalyticsUserProperty] = []

    public init() {}

    /// 撃たれた出来事（撃たれた順）。
    public var events: [any AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    /// 撃たれた出来事の名前（撃たれた順）。**重複はそのまま残す。**
    public var names: [String] {
        events.map(\.name)
    }

    /// `name key=value` の形で並べたもの。パラメータまで固定したいときに使う。
    public var lines: [String] {
        events.map(\.debugLine)
    }

    /// 置かれた属性（置かれた順）。
    public var properties: [any AnalyticsUserProperty] {
        lock.lock()
        defer { lock.unlock() }
        return storedProperties
    }

    /// `name=value` の形で並べたもの。
    public var propertyLines: [String] {
        properties.map { "\($0.name)=\($0.value)" }
    }

    /// ある名前が何回撃たれたか。**1 回であることを確かめるのに使う。**
    public func count(of name: String) -> Int {
        names.filter { $0 == name }.count
    }

    public func track(_ event: any AnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.append(event)
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        lock.lock()
        defer { lock.unlock() }
        storedProperties.append(property)
    }

    /// 記録を捨てる。1 つのテストで局面を分けたいときに使う。
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.removeAll()
        storedProperties.removeAll()
    }
}
