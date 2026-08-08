/// 計測の送信口。
///
/// 実装（Firebase / PostHog / 自前のサーバー）はこのパッケージに入れない。
/// パッケージ本体が vendor に依存すると、Swift Package Manager は依存をパッケージ単位で
/// 解決するので、**語彙しか使わない消費者にまで vendor の SDK が降ってくる**。
///
/// アダプタはアプリ側に 20 行書くか、`swift-analytics-firebase` のような
/// 別パッケージから足す。
///
/// ## 送信は fire-and-forget
///
/// 戻り値も `throws` も持たない。計測の失敗や遅延がアプリの動作に波及する経路を作らない
/// ——「ログが送れないので操作を止める」は、どんな場合も割に合わない。
public protocol AnalyticsClient: Sendable {

    /// 出来事を 1 つ送る。
    func track(_ event: any AnalyticsEvent)

    /// その人に貼り付ける属性を置き直す。同じ値を何度置いてもよい。
    func setUserProperty(_ property: any AnalyticsUserProperty)
}

/// 何もしない実装。テスト・プレビュー・鍵が未設定のときの既定。
///
/// 計測が落ちてもアプリは何も壊れない、を型で示す。
public struct NoopAnalytics: AnalyticsClient {

    public init() {}

    public func track(_ event: any AnalyticsEvent) {}

    public func setUserProperty(_ property: any AnalyticsUserProperty) {}
}

/// 同じ出来事を複数の送信先へ流す。
///
/// 開発中に「コンソールで確かめながら本番にも送る」ために使う。
/// 送信先を乗り換える途中で 2 系統を並走させ、履歴を切らさないためにも使える。
public struct MultiplexAnalytics: AnalyticsClient {

    private let clients: [any AnalyticsClient]

    /// - Parameter clients: 流す先。**渡した順に呼ぶ。**
    public init(_ clients: [any AnalyticsClient]) {
        self.clients = clients
    }

    public func track(_ event: any AnalyticsEvent) {
        for client in clients { client.track(event) }
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        for client in clients { client.setUserProperty(property) }
    }
}
