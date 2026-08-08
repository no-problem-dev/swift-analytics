import AnalyticsCore
import SwiftUI

private struct AnalyticsClientKey: EnvironmentKey {
    static let defaultValue: any AnalyticsClient = NoopAnalytics()
}

public extension EnvironmentValues {

    /// 画面から計測へ届く口。
    ///
    /// 既定は ``AnalyticsCore/NoopAnalytics`` なので、プレビューもテストも配線なしで動く。
    ///
    /// ストアではなく Environment に置くのは、発火点が「画面が出た」「ボタンが押された」という
    /// View の出来事だから。ストアに持たせると、状態を持たない画面が計測のためだけに
    /// ストアを要ることになる。
    var analytics: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}

public extension View {

    /// 計測の実体を配る。**合成ルートがルートで 1 度だけ張る。**
    func analytics(_ client: any AnalyticsClient) -> some View {
        environment(\.analytics, client)
    }
}
