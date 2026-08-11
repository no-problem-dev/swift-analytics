import AnalyticsCore
import Testing
@testable import AnalyticsSwiftUI

@MainActor
@Suite("端末で読む計測ログ")
struct AnalyticsLogTests {

    @Test("新しいものが先頭に来る")
    func keepsNewestFirst() {
        let log = AnalyticsLog()
        log.record(Event(name: "first"))
        log.record(Event(name: "second"))

        #expect(log.entries.map(\.name) == ["second", "first"])
    }

    @Test("上限を超えたら古いものから捨てる")
    func dropsOldestBeyondLimit() {
        let log = AnalyticsLog(limit: 2)
        for name in ["a", "b", "c"] { log.record(Event(name: name)) }

        #expect(log.entries.map(\.name) == ["c", "b"])
    }

    @Test("引数は鍵で整列して 1 行になる")
    func rendersParameters() {
        let log = AnalyticsLog()
        log.record(Event(name: "paywall_shown", parameters: ["source": .text("teaser"), "count": .count(2)]))

        #expect(log.entries.first?.detail == "count=2  source=teaser")
    }

    @Test("種別と数え方も控える（期待とのずれを目で見つけるため）")
    func keepsKindAndDedup() {
        let log = AnalyticsLog()
        log.record(Event(name: "paywall_shown"))

        #expect(log.entries.first?.kind == .screen)
        #expect(log.entries.first?.dedup == .always)
    }

    @Test("属性は出来事と区別して残る")
    func marksProperties() {
        let log = AnalyticsLog()
        log.record(Property(name: "plan", value: "free"))

        #expect(log.entries.first?.isProperty == true)
        #expect(log.entries.first?.detail == "free")
    }

    @Test("同じ名前が何回出たか数えられる（出すぎに気づくため）")
    func countsRepeats() {
        let log = AnalyticsLog()
        log.record(Event(name: "tutorial_begin"))
        log.record(Event(name: "tutorial_begin"))

        #expect(log.count(of: "tutorial_begin") == 2)
    }

    @Test("消すと空になる")
    func clears() {
        let log = AnalyticsLog()
        log.record(Event(name: "a"))
        log.clear()

        #expect(log.entries.isEmpty)
    }
}

private struct Event: AnalyticsEvent {
    let name: String
    var parameters: [String: AnalyticsValue] = [:]
    var kind: EventKind { .screen }
    var dedup: DedupScope { .always }
}

private struct Property: AnalyticsUserProperty {
    let name: String
    let value: String
}
