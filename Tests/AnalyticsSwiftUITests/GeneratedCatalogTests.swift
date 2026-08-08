import AnalyticsCore
import Foundation
import AnalyticsTesting
import Testing
@testable import AnalyticsSwiftUI

/// `Scripts/analytics-gen.py` が書き出したものが、実際に使える形になっていること。
///
/// このテストの存在自体が契約になっている —— `Generated/ExampleAnalytics.swift` は
/// `Schema/example.yaml` から生成しており、**生成物がコンパイルできなくなればここで落ちる**。
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
        // 生の件数を送らないための型。**帯にするかどうかを撃つ側が選べない**のが要点。
        #expect(ExampleUserProperty.itemsBucket(0).value == "0")
        #expect(ExampleUserProperty.itemsBucket(3).value == "1_5")
        #expect(ExampleUserProperty.itemsBucket(40).value == "16_plus")
        #expect(ExampleUserProperty.plan(.paid).value == "paid")
    }

    @Test("型付きの入口があるので、発火点で先頭ドットが使える")
    func keepsLeadingDotSyntax() {
        let analytics = RecordingAnalytics()
        // ポートは `any AnalyticsEvent` を受け取るので、生成された overload が無いと
        // この行はコンパイルできない。**書き味が保たれていることをここで固定する。**
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

        // 発火点に「もう撃ったか」を書いていないのに 1 回になる
        #expect(recorder.count(of: "stock_first_record") == 1)
    }
}
