import AnalyticsCore
import Foundation
import Observation

/// 出た回数を数えて画面に出すだけの送信口。
///
/// **XCUITest が読むのはこの数字。** スクリーンショットの目視では回数のずれを見つけられない
/// ——「1 回のはずが 2 回」も「戻ってきたのに数え直していない」も、絵は同じになる。
@MainActor
@Observable
final class ProbeRecorder: AnalyticsClient {
    private(set) var counts: [String: Int] = [:]

    nonisolated func track(_ event: any AnalyticsEvent) {
        let name = event.name
        Task { @MainActor in counts[name, default: 0] += 1 }
    }

    nonisolated func setUserProperty(_ property: any AnalyticsUserProperty) {}

    func reset() { counts.removeAll() }

    /// `screen=1 row=0 …` の形。XCUITest はこの 1 本の文字列だけを見る。
    var readout: String {
        ProbeEvent.allCases
            .map { "\($0.rawValue)=\(counts[$0.rawValue] ?? 0)" }
            .joined(separator: " ")
    }
}

/// 起動引数で変えられる設定。
///
/// 「1 秒たたずに離れたら数えない」を確かめるには、**テストの操作が滞在時間より速く
/// 終わる保証**が要る。シミュレータの遷移アニメーションは端末や負荷で伸びるので、
/// そこだけ滞在時間を延ばして確実に間に合わせる。
enum ProbeConfig {
    static var dwell: TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-dwell"), index + 1 < arguments.count,
              let value = Double(arguments[index + 1]) else { return 1.0 }
        return value
    }
}
