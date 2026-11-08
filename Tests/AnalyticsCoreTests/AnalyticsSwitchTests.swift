import Foundation
import os
import Testing
@testable import AnalyticsCore
import AnalyticsTesting

/// The person's off switch stops everything, remembers the choice, and erases what was kept.
@Suite("送信の止め")
struct AnalyticsSwitchTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "swift-analytics.tests.\(UUID().uuidString)")!
    }

    @Test("何も選んでいなければ送る（オプトアウト）")
    func sendsByDefault() {
        let recorder = RecordingAnalytics()
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults())

        analytics.track(Event(name: "app_opened"))
        analytics.setUserProperty(Property(name: "plan", value: "free"))

        #expect(analytics.isEnabled)
        #expect(recorder.names == ["app_opened"])
        #expect(recorder.propertyLines == ["plan=free"])
    }

    @Test("止めたら出来事も属性も通さず、止めの処理を待つ")
    func dropsEverythingWhenOff() async {
        let recorder = RecordingAnalytics()
        let erased = OSAllocatedUnfairLock(initialState: 0)
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults()) {
            erased.withLock { $0 += 1 }
        }

        await analytics.setEnabled(false)
        analytics.track(Event(name: "app_opened"))
        analytics.setUserProperty(Property(name: "plan", value: "free"))

        #expect(!analytics.isEnabled)
        #expect(recorder.events.isEmpty)
        #expect(recorder.properties.isEmpty)
        #expect(erased.withLock { $0 } == 1)
    }

    @Test("選んだ状態は次の起動でも残る")
    func remembersChoice() async {
        let defaults = makeDefaults()
        await AnalyticsSwitch(RecordingAnalytics(), defaults: defaults).setEnabled(false)

        let recorder = RecordingAnalytics()
        let relaunched = AnalyticsSwitch(recorder, defaults: defaults)
        relaunched.track(Event(name: "app_opened"))

        #expect(!relaunched.isEnabled)
        #expect(recorder.events.isEmpty)
    }

    @Test("オンに戻すと送り、止めの処理は呼ばない")
    func resumes() async {
        let recorder = RecordingAnalytics()
        let erased = OSAllocatedUnfairLock(initialState: 0)
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults()) {
            erased.withLock { $0 += 1 }
        }

        await analytics.setEnabled(false)
        await analytics.setEnabled(true)
        analytics.track(Event(name: "app_opened"))

        #expect(recorder.names == ["app_opened"])
        #expect(erased.withLock { $0 } == 1)
    }

    @Test("enabledByDefault: false なら、選ぶまで送らない（オプトイン）")
    func optIn() {
        let recorder = RecordingAnalytics()
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults(), enabledByDefault: false)

        analytics.track(Event(name: "app_opened"))

        #expect(recorder.events.isEmpty)
    }

    @Test("同期の setEnabled(false) は戻る前に止め、消すのは返したタスクで行う")
    func stopsSynchronously() async {
        let recorder = RecordingAnalytics()
        let erased = OSAllocatedUnfairLock(initialState: 0)
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults()) {
            erased.withLock { $0 += 1 }
        }

        let erasure = stopFromSyncCode(analytics)
        analytics.track(Event(name: "right_after"))
        #expect(!analytics.isEnabled)
        #expect(recorder.events.isEmpty)

        await erasure.value
        #expect(erased.withLock { $0 } == 1)
    }

    @Test("同期の setEnabled(true) は消さずに送りを戻す")
    func resumesSynchronously() async {
        let recorder = RecordingAnalytics()
        let erased = OSAllocatedUnfairLock(initialState: 0)
        let analytics = AnalyticsSwitch(recorder, defaults: makeDefaults(), enabledByDefault: false) {
            erased.withLock { $0 += 1 }
        }

        await resumeFromSyncCode(analytics).value
        analytics.track(Event(name: "app_opened"))

        #expect(recorder.names == ["app_opened"])
        #expect(erased.withLock { $0 } == 0)
    }

    @Test("外側に置けば、止めている間の出来事は install の窓を使わない")
    func outsideDedupKeepsInstallWindow() async {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()
        let analytics = AnalyticsSwitch(DedupingAnalytics(recorder, defaults: defaults), defaults: defaults)

        await analytics.setEnabled(false)
        analytics.track(Event(name: "first_trip", dedup: .install))
        await analytics.setEnabled(true)
        analytics.track(Event(name: "first_trip", dedup: .install))

        #expect(recorder.count(of: "first_trip") == 1)
    }
}

/// A toggle's action: synchronous code, where only the synchronous overload is visible.
private func stopFromSyncCode(_ analytics: AnalyticsSwitch) -> Task<Void, Never> {
    analytics.setEnabled(false)
}

private func resumeFromSyncCode(_ analytics: AnalyticsSwitch) -> Task<Void, Never> {
    analytics.setEnabled(true)
}

private struct Event: AnalyticsEvent {
    let name: String
    var dedup: DedupScope = .always
    var parameters: [String: AnalyticsValue] { [:] }
    var kind: EventKind { .interaction }
}

private struct Property: AnalyticsUserProperty {
    let name: String
    let value: String
}
