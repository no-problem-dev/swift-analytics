// swift-tools-version: 6.2
import PackageDescription

/// Vocabulary for product analytics, and the tools to count it correctly in SwiftUI.
///
/// **No external dependencies.** Vendor SDKs (Firebase, PostHog, and the like) do not belong here:
/// SwiftPM resolves dependencies per package, so bundling one would pull it into consumers that
/// only use the vocabulary. Adapters live in a separate package such as `swift-analytics-firebase`,
/// or in twenty lines inside the app.
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
        // Vocabulary, ports, counting rules. Depends on nothing beyond Foundation, not even SwiftUI.
        .library(name: "AnalyticsCore", targets: ["AnalyticsCore"]),
        // The layer that fires from a view tree. Depends only on SwiftUI.
        .library(name: "AnalyticsSwiftUI", targets: ["AnalyticsSwiftUI"]),
        // Test doubles. **Never import this from a shipping target.**
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
