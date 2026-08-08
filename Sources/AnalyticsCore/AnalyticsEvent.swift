/// アプリで起きた 1 つの出来事。
///
/// 準拠する型は**アプリごとに生成する**（`Scripts/analytics-gen.py` が `analytics.yaml` から書き出す）。
/// 手で書いてもよいが、そのときも生成物と同じ形を保つこと —— 生成に切り替えるときに
/// 発火点を書き換えずに済む。
///
/// ## 名前とパラメータは型から導く
///
/// 文字列でイベントを送る口をライブラリは持たない。綴りの揺れも、カタログに無いイベントも、
/// コンパイルできない状態を保つための制約。
///
/// ## 載せてよいもの
///
/// 列挙値と数値だけ。**品名・表示名・メールアドレス・招待コードのような、人が書いた文字列は
/// 載せない。** 集計に出す理由が無く、いちど送ると取り消せない。
/// 生の件数も、粒度によっては個人を指すので ``AnalyticsValue/bucket(_:edges:)`` で帯にする。
public protocol AnalyticsEvent: Sendable {

    /// 送信先へ渡す名前。snake_case で、領域のプレフィクスを付ける（`ob_` / `paywall_` など）。
    var name: String { get }

    /// この出来事に固有の値。
    var parameters: [String: AnalyticsValue] { get }

    /// どういう類の出来事か。**発火の仕組みはここから選ばれる。**
    var kind: EventKind { get }

    /// どの範囲で 1 回と数えるか。**発火点はこれを書かない。**
    var dedup: DedupScope { get }
}

public extension AnalyticsEvent {

    /// 「一生に 1 回」「起動中に 1 回」を覚えておくための鍵。
    ///
    /// 既定では名前だけを使い、パラメータを見ない。たとえば「初めて通知に応えた」は、
    /// 段階が `low` でも `soon` でも 1 回であって、段階ごとに 1 回ずつではない。
    ///
    /// パラメータの値ごとに 1 回ずつ数えたいときだけ、準拠側で上書きする。
    var dedupKey: String { name }

    /// ログや検証に出すための 1 行表現。`name key=value key=value` の形。
    ///
    /// パラメータの順序は鍵で整列する —— 辞書の並びは実行のたびに変わるので、
    /// そのまま出すとテストの期待値にできない。
    var debugLine: String {
        guard !parameters.isEmpty else { return name }
        let rendered = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: " ")
        return "\(name) \(rendered)"
    }
}

/// その人に貼り付けておく属性。出来事ではなく「いまどうなっているか」。
///
/// 出来事と違い、同じ値を何度置いても結果は変わらない。だから遷移を追う必要が無く、
/// 状態が分かる場所で置き直せばよい。
public protocol AnalyticsUserProperty: Sendable {
    /// 送信先へ渡す名前。
    var name: String { get }
    /// 値。列挙の raw 値か、帯に落とした数値だけを入れる。
    var value: String { get }
}
