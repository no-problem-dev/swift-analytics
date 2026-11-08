import Foundation
import Testing
@testable import AnalyticsCore
import AnalyticsTesting

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "swift-analytics.tests.\(UUID().uuidString)")!
}

@Suite("インストールの ID")
struct InstallIDTests {

    @Test("初めて読んだときに UUID を作って保存し、次からは同じものを返す")
    func makesOnceAndKeeps() throws {
        let defaults = makeDefaults()
        let first = InstallID.current(defaults: defaults)
        #expect(UUID(uuidString: first) != nil)
        #expect(first == first.lowercased())
        #expect(InstallID.current(defaults: defaults) == first)
    }

    @Test("reset すると新しい ID になる。UUID でない値は作り直す")
    func resetsAndRepairs() {
        let defaults = makeDefaults()
        let first = InstallID.current(defaults: defaults)
        InstallID.reset(defaults: defaults)
        #expect(InstallID.current(defaults: defaults) != first)

        defaults.set("not-a-uuid", forKey: InstallID.key)
        #expect(UUID(uuidString: InstallID.current(defaults: defaults)) != nil)
    }
}

@Suite("前の版の install ID を引き継ぐ")
struct InstallIDAdoptTests {

    @Test("まだ無ければ渡した ID を小文字で保存し、current がそれを返す")
    func adoptsWhenEmpty() {
        let defaults = makeDefaults()
        let legacy = "8C1F2A4E-0B7D-4E8A-9C3B-1D2E3F405162"
        #expect(InstallID.adopt(legacy, defaults: defaults))
        #expect(InstallID.current(defaults: defaults) == legacy.lowercased())
    }

    @Test("もうあれば替えない。UUID でない値は受けない")
    func keepsExistingAndRejectsNonUUID() {
        let defaults = makeDefaults()
        #expect(!InstallID.adopt("legacy-id", defaults: defaults))
        let made = InstallID.current(defaults: defaults)
        #expect(!InstallID.adopt(UUID().uuidString, defaults: defaults))
        #expect(InstallID.current(defaults: defaults) == made)
    }
}

@Suite("インストールでの回数")
struct OccurrenceCountTests {

    @Test("next は 1 から数え、鍵ごとに分かれ、current は足さない")
    func countsPerKey() {
        let defaults = makeDefaults()
        #expect(OccurrenceCount.current("paywall_shown", defaults: defaults) == 0)
        #expect(OccurrenceCount.next("paywall_shown", defaults: defaults) == 1)
        #expect(OccurrenceCount.next("paywall_shown", defaults: defaults) == 2)
        #expect(OccurrenceCount.next("whats_new_shown", defaults: defaults) == 1)
        #expect(OccurrenceCount.current("paywall_shown", defaults: defaults) == 2)
    }

    @Test("reset は 1 つ、resetAll は全部を忘れる。ほかの鍵には触らない")
    func resets() {
        let defaults = makeDefaults()
        defaults.set("keep", forKey: "app.other")
        OccurrenceCount.next("a", defaults: defaults)
        OccurrenceCount.next("b", defaults: defaults)
        OccurrenceCount.reset("a", defaults: defaults)
        #expect(OccurrenceCount.current("a", defaults: defaults) == 0)
        #expect(OccurrenceCount.current("b", defaults: defaults) == 1)
        OccurrenceCount.resetAll(defaults: defaults)
        #expect(OccurrenceCount.current("b", defaults: defaults) == 0)
        #expect(defaults.string(forKey: "app.other") == "keep")
    }

    @Test("同時に数えても取りこぼさない")
    func concurrent() async {
        let defaults = makeDefaults()
        nonisolated(unsafe) let shared = defaults
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { OccurrenceCount.next("x", defaults: shared) }
            }
        }
        #expect(OccurrenceCount.current("x", defaults: defaults) == 100)
    }
}

@Suite("ビルドの経路")
struct BuildChannelTests {

    @Test("Debug・シミュレータ・開発用の署名は debug")
    func debugWins() {
        #expect(BuildChannel.resolve(isDebugBuild: true, isSimulator: false, hasEmbeddedProvisioningProfile: false, receiptName: "receipt") == .debug)
        #expect(BuildChannel.resolve(isDebugBuild: false, isSimulator: true, hasEmbeddedProvisioningProfile: false, receiptName: "sandboxReceipt") == .debug)
        #expect(BuildChannel.resolve(isDebugBuild: false, isSimulator: false, hasEmbeddedProvisioningProfile: true, receiptName: "sandboxReceipt") == .debug)
    }

    @Test("sandbox のレシートは TestFlight、それ以外は App Store")
    func receiptDecides() {
        #expect(BuildChannel.resolve(isDebugBuild: false, isSimulator: false, hasEmbeddedProvisioningProfile: false, receiptName: "sandboxReceipt") == .testflight)
        #expect(BuildChannel.resolve(isDebugBuild: false, isSimulator: false, hasEmbeddedProvisioningProfile: false, receiptName: "receipt") == .appstore)
        #expect(BuildChannel.resolve(isDebugBuild: false, isSimulator: false, hasEmbeddedProvisioningProfile: false, receiptName: nil) == .appstore)
    }

    @Test("値は封筒の channel の綴り")
    func rawValues() {
        #expect(BuildChannel.allCases.map(\.rawValue) == ["debug", "testflight", "appstore"])
    }
}

@Suite("初めての起動")
struct FirstLaunchTests {

    @Test("アプリが前に自分の規則で送っていれば（sentBefore）送らず、送った印だけ残す")
    func respectsTheAppsOwnRecord() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()
        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, sentBefore: true, defaults: defaults) == nil)
        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults) == nil)
        #expect(recorder.count(of: "first_open") == 0)
    }

    @Test("新しく入れた端末では first_open{kind: fresh} を1回だけ送る")
    func sendsFreshOnce() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults, now: start) == .fresh)
        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults, now: start) == nil)

        #expect(recorder.count(of: "first_open") == 1)
        #expect(recorder.events.first?.parameters == ["kind": .text("fresh")])
        #expect(FirstLaunch.daysSince(defaults: defaults, now: start.addingTimeInterval(86_400 * 3)) == 3)
    }

    @Test("前の版が起動の時刻を残していれば upgraded")
    func upgradedFromEarlierStamp() {
        let defaults = makeDefaults()
        defaults.set(1_700_000_000.0, forKey: "analytics.firstLaunchAt")
        let recorder = RecordingAnalytics()

        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults) == .upgraded)
        // 時刻は前の版のまま（上書きしない）
        #expect(defaults.double(forKey: "analytics.firstLaunchAt") == 1_700_000_000)
    }

    @Test("アプリが前の版のデータを持っていると言えば upgraded")
    func upgradedFromPriorData() {
        let recorder = RecordingAnalytics()
        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, hasPriorData: true, defaults: makeDefaults()) == .upgraded)
        #expect(recorder.events.first?.parameters == ["kind": .text("upgraded")])
    }

    @Test("reset の後はまた初めての起動として扱う")
    func resetStartsOver() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()
        FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults)
        FirstLaunch.reset(defaults: defaults)
        #expect(FirstLaunch.recordLaunch(sendingTo: recorder, defaults: defaults) == .fresh)
    }
}

@Suite("作り手の端末")
struct InternalDeviceTests {

    @Test("印を付けたときに internal_device を1回だけ送り、印を残す")
    func marksOnce() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()

        #expect(!AnalyticsInternalDevice.isInternal(defaults: defaults))
        #expect(AnalyticsInternalDevice.mark(sendingTo: recorder, defaults: defaults))
        #expect(!AnalyticsInternalDevice.mark(sendingTo: recorder, defaults: defaults))

        #expect(AnalyticsInternalDevice.isInternal(defaults: defaults))
        #expect(recorder.count(of: "internal_device") == 1)
    }

    @Test("sendAgain なら印があっても送り直す（uid が替わったとき）")
    func sendsAgainWhenAsked() {
        let defaults = makeDefaults()
        let recorder = RecordingAnalytics()
        AnalyticsInternalDevice.mark(sendingTo: recorder, defaults: defaults)
        #expect(AnalyticsInternalDevice.mark(sendingTo: recorder, defaults: defaults, sendAgain: true))
        #expect(recorder.count(of: "internal_device") == 2)
    }

    @Test("パッケージが送る出来事は install で数える outcome")
    func commonEventShape() {
        #expect(CommonEvent.internalDevice.dedup == .install)
        #expect(CommonEvent.firstOpen(kind: .fresh).kind == .outcome)
        #expect(FirstOpenKind.allCases.map(\.rawValue) == ["fresh", "upgraded"])
    }
}
