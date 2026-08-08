/// パラメータに載せられる値。
///
/// `Any` を許さないのは、送信先ごとに扱える型が違い、**扱えない型は黙って捨てられる**から。
/// たとえば GA4 は配列も辞書も受け取らず、送信は成功したように見えてダッシュボードに出ない。
/// ここで型を絞っておけば、送る前にコンパイラが止める。
public enum AnalyticsValue: Sendable, Equatable {

    /// 列挙の raw 値。**人が書いた文字列を入れない**（品名・表示名・自由入力）。
    case text(String)

    /// 個数・日数などの整数。
    case count(Int)

    /// 割合・秒などの実数。
    case number(Double)

    /// 真偽。送信先によっては数値に落とす（``ga4Encoded``）。
    case flag(Bool)

    /// 数値を帯に落とす。
    ///
    /// 生の件数は、粒度によっては個人を指す（「アイテム 137 件の人」は 1 人しか居ない）。
    /// 集計に必要なのはたいてい大小の別なので、境界を決めて帯にする。
    ///
    /// ```swift
    /// AnalyticsValue.bucket(0, edges: [1, 6, 16])   // "0"
    /// AnalyticsValue.bucket(3, edges: [1, 6, 16])   // "1_5"
    /// AnalyticsValue.bucket(99, edges: [1, 6, 16])  // "16_plus"
    /// ```
    ///
    /// - Parameters:
    ///   - value: 元の数値
    ///   - edges: 帯の下限。**昇順**で渡す
    public static func bucket(_ value: Int, edges: [Int]) -> AnalyticsValue {
        let sorted = edges.sorted()
        guard let first = sorted.first, value >= first else {
            return .text(String(sorted.first.map { $0 - 1 } ?? 0))
        }
        for (index, lower) in sorted.enumerated() {
            let upper = index + 1 < sorted.count ? sorted[index + 1] : nil
            guard let upper else { return .text("\(lower)_plus") }
            if value < upper { return .text("\(lower)_\(upper - 1)") }
        }
        return .text("\(first)_plus")
    }
}

extension AnalyticsValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .text(value): return value
        case let .count(value): return String(value)
        case let .number(value): return String(value)
        case let .flag(value): return value ? "true" : "false"
        }
    }
}
