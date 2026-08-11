import Foundation
import Testing
@testable import AnalyticsCore
import AnalyticsTesting

/// The counting rules the catalog holds take effect without any firing point writing them down.
@Suite("数え方の実施")
struct DedupingAnalyticsTests {

    /// A `UserDefaults` suite of its own. Polluting the standard one would make the results of
    /// other tests depend on the order they run in.
    private func makeDefaults() -> UserDefaults {
        let suite = "swift-analytics.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("always は毎回通す")
    func passesAlways() {
        let recorder = RecordingAnalytics()
        let analytics = DedupingAnalytics(recorder, defaults: makeDefaults())

        analytics.track(TestEvent(name: "tapped", dedup: .always))
        analytics.track(TestEvent(name: "tapped", dedup: .always))

        #expect(recorder.count(of: "tapped") == 2)
    }

    @Test("session は起動中に 1 回だけ通す")
    func collapsesWithinSession() {
        let recorder = RecordingAnalytics()
        let analytics = DedupingAnalytics(recorder, defaults: makeDefaults())

        analytics.track(TestEvent(name: "paywall_seen", dedup: .session))
        analytics.track(TestEvent(name: "paywall_seen", dedup: .session))

        #expect(recorder.count(of: "paywall_seen") == 1)
    }

    @Test("install は起動をまたいで 1 回だけ通す")
    func collapsesAcrossLaunches() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()

        DedupingAnalytics(recorder, defaults: defaults)
            .track(TestEvent(name: "first_record", dedup: .install))
        // A separate instance stands in for the app having been launched again
        DedupingAnalytics(recorder, defaults: defaults)
            .track(TestEvent(name: "first_record", dedup: .install))

        #expect(recorder.count(of: "first_record") == 1)
    }

    @Test("同じ出来事なら、パラメータが違っても install は 1 回")
    func installIgnoresParameters() {
        let recorder = RecordingAnalytics()
        let analytics = DedupingAnalytics(recorder, defaults: makeDefaults())

        analytics.track(TestEvent(name: "first_alert", dedup: .install, parameters: ["stage": .text("low")]))
        analytics.track(TestEvent(name: "first_alert", dedup: .install, parameters: ["stage": .text("soon")]))

        #expect(recorder.count(of: "first_alert") == 1)
    }

    @Test("episode はここでは触らない（画面の概念なので ImpressionTracker が持つ）")
    func leavesEpisodeToTheView() {
        let recorder = RecordingAnalytics()
        let analytics = DedupingAnalytics(recorder, defaults: makeDefaults())

        analytics.track(TestEvent(name: "screen", dedup: .episode))
        analytics.track(TestEvent(name: "screen", dedup: .episode))

        #expect(recorder.count(of: "screen") == 2)
    }

    @Test("属性は間引かない")
    func neverCollapsesProperties() {
        let recorder = RecordingAnalytics()
        let analytics = DedupingAnalytics(recorder, defaults: makeDefaults())

        analytics.setUserProperty(TestProperty(name: "plan", value: "free"))
        analytics.setUserProperty(TestProperty(name: "plan", value: "free"))

        #expect(recorder.propertyLines == ["plan=free", "plan=free"])
    }
}

// MARK: - Minimal conformances for the tests

private struct TestEvent: AnalyticsEvent {
    let name: String
    let dedup: DedupScope
    var parameters: [String: AnalyticsValue] = [:]
    var kind: EventKind { .interaction }
}

private struct TestProperty: AnalyticsUserProperty {
    let name: String
    let value: String
}
