import AnalyticsCore

/// 確かめたい発火だけを持つ最小のカタログ。
///
/// 本物のアプリのカタログは `analytics.yaml` から生成するが、ここで確かめたいのは
/// **カタログの中身ではなく繋ぎのほう**なので、手で書いた 4 つで足りる。
enum ProbeEvent: String, AnalyticsEvent, CaseIterable {
    /// 画面（`trackScreen`）。
    case screen = "screen"
    /// シートの中の画面。
    case sheet = "sheet"
    /// スクロールの中の要素（`trackImpression`）。
    case row = "row"
    /// 画面外に置いた要素。**ここが 1 以上になったら H3 を踏んでいる。**
    case offscreen = "offscreen"

    var name: String { rawValue }
    var parameters: [String: AnalyticsValue] { [:] }
    var kind: EventKind { self == .row || self == .offscreen ? .impression : .screen }
    var dedup: DedupScope { .episode }
}
