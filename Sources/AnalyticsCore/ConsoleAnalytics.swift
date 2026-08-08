import Foundation
import os

/// 送るはずの出来事を `os.Logger` に流すだけの実装。
///
/// 送信先のデバッグ画面は反映に間があるので、「いまこの操作で何が出たか」を追うのに使う。
/// 本番送信の代わりではなく、``MultiplexAnalytics`` で並べて両方走らせる。
///
/// ```swift
/// #if DEBUG
/// let analytics = MultiplexAnalytics([ConsoleAnalytics(), firebase])
/// #else
/// let analytics = firebase
/// #endif
/// ```
///
/// 値は `privacy: .public` で出す。載っているのは列挙値と数値だけ（``AnalyticsValue``）で、
/// 人が書いた文字列は最初から入らないため。
public struct ConsoleAnalytics: AnalyticsClient {

    private let logger: Logger

    /// - Parameters:
    ///   - subsystem: 既定は `dev.no-problem.swift-analytics`。アプリ側の識別子を渡してよい
    ///   - category: 既定は `analytics`
    public init(
        subsystem: String = "dev.no-problem.swift-analytics",
        category: String = "analytics"
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func track(_ event: any AnalyticsEvent) {
        logger.info("event \(event.debugLine, privacy: .public)")
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        logger.info("property \(property.name, privacy: .public)=\(property.value, privacy: .public)")
    }
}
