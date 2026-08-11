import AnalyticsCore
import Foundation
import AnalyticsTesting
import Testing
@testable import AnalyticsSwiftUI

/// What `Scripts/analytics-gen.py` writes out comes back in a shape that is actually usable.
///
/// The existence of this test is itself the contract — `Generated/ExampleAnalytics.swift` is
/// generated from `Schema/example.yaml`, and **the moment the generated code stops compiling,
/// this is where it fails**.
@Suite("生成したカタログ")
struct GeneratedCatalogTests {

    @Test("名前・種別・数え方がスキーマどおり")
    func carriesSchemaFacts() {
        #expect(ExampleEvent.tutorialBegin.name == "tutorial_begin")
        #expect(ExampleEvent.tutorialBegin.kind == .screen)
        #expect(ExampleEvent.tutorialBegin.dedup == .episode)

        #expect(ExampleEvent.paywallShown(source: .soloCard).kind == .impression)
        #expect(ExampleEvent.stockFirstRecord(day: 0).dedup == .install)
    }

    @Test("enum の値は snake_case のまま送られる")
    func sendsRawValues() {
        let event = ExampleEvent.paywallShown(source: .gate402)
        #expect(event.parameters["source"] == .text("gate_402"))
    }

    @Test("数値のパラメータは型を保って載る")
    func carriesNumbers() {
        #expect(ExampleEvent.tutorialComplete(items: 3).parameters["items"] == .count(3))
    }

    @Test("bucket 型の属性は帯に落ちる")
    func bucketsProperties() {
        // A type that keeps raw counts from being sent. The point is that **the caller cannot
        // choose whether to band it.**
        #expect(ExampleUserProperty.itemsBucket(0).value == "0")
        #expect(ExampleUserProperty.itemsBucket(3).value == "1_5")
        #expect(ExampleUserProperty.itemsBucket(40).value == "16_plus")
        #expect(ExampleUserProperty.plan(.paid).value == "paid")
    }

    @Test("型付きの入口があるので、発火点で先頭ドットが使える")
    func keepsLeadingDotSyntax() {
        let analytics = RecordingAnalytics()
        // The port takes `any AnalyticsEvent`, so without the generated overload this line does
        // not compile. **Pin here that it still reads the way it should.**
        analytics.track(.tutorialBegin)
        analytics.track(.paywallShown(source: .teaser))
        analytics.setUserProperty(.plan(.free))

        #expect(analytics.lines == ["tutorial_begin", "paywall_shown source=teaser"])
        #expect(analytics.propertyLines == ["plan=free"])
    }

    @Test("カタログの数え方は DedupingAnalytics がそのまま実施する")
    func honoursCatalogDedup() {
        let recorder = RecordingAnalytics()
        let defaults = UserDefaults(suiteName: "swift-analytics.tests.generated")!
        defaults.removePersistentDomain(forName: "swift-analytics.tests.generated")
        let analytics = DedupingAnalytics(recorder, defaults: defaults)

        analytics.track(ExampleEvent.stockFirstRecord(day: 0))
        analytics.track(ExampleEvent.stockFirstRecord(day: 4))

        // Comes out once, with no firing point asking whether it already fired
        #expect(recorder.count(of: "stock_first_record") == 1)
    }
}
