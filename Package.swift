// swift-tools-version: 6.2
import PackageDescription

/// プロダクト分析のための語彙と、SwiftUI で正しく数えるための道具。
///
/// **外部依存ゼロ。** vendor（Firebase / PostHog など）はここに入れない ——
/// SwiftPM は依存をパッケージ単位で解決するので、同居させると語彙しか使わない消費者にも
/// vendor の SDK が降ってくる。アダプタは `swift-analytics-firebase` のような別パッケージか、
/// アプリ側の 20 行に置く。
let package = Package(
    name: "swift-analytics",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // 語彙・ポート・数え方。SwiftUI にも Foundation の外にも依存しない中核。
        .library(name: "AnalyticsCore", targets: ["AnalyticsCore"]),
        // 画面から撃つための層。SwiftUI にだけ依存する。
        .library(name: "AnalyticsSwiftUI", targets: ["AnalyticsSwiftUI"]),
        // テストの土台。**製品ターゲットからは import しない。**
        .library(name: "AnalyticsTesting", targets: ["AnalyticsTesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")
    ],
    targets: [
        .target(name: "AnalyticsCore"),
        .target(name: "AnalyticsSwiftUI", dependencies: ["AnalyticsCore"]),
        .target(name: "AnalyticsTesting", dependencies: ["AnalyticsCore"]),

        .testTarget(name: "AnalyticsCoreTests", dependencies: ["AnalyticsCore", "AnalyticsTesting"]),
        .testTarget(name: "AnalyticsSwiftUITests", dependencies: ["AnalyticsSwiftUI", "AnalyticsTesting"])
    ]
)
