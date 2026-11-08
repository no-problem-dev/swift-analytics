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

        #expect(!InternalDevice.isInternal(defaults: defaults))
        #expect(InternalDevice.mark(sendingTo: recorder, defaults: defaults))
        #expect(!InternalDevice.mark(sendingTo: recorder, defaults: defaults))

        #expect(InternalDevice.isInternal(defaults: defaults))
        #expect(recorder.count(of: "internal_device") == 1)
    }

    @Test("パッケージが送る出来事は install で数える outcome")
    func commonEventShape() {
        #expect(CommonEvent.internalDevice.dedup == .install)
        #expect(CommonEvent.firstOpen(kind: .fresh).kind == .outcome)
        #expect(FirstOpenKind.allCases.map(\.rawValue) == ["fresh", "upgraded"])
    }
}
