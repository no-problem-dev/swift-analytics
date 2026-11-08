import Testing
@testable import AnalyticsCore

@Suite("送れる値")
struct AnalyticsValueTests {

    @Test("帯の名前をアプリが決められる（1つ目は一番下の境界より下）")
    func labelledBuckets() {
        let edges = [1, 2, 10]
        let labels = ["0", "1", "2_9", "10+"]
        #expect(AnalyticsValue.bucket(-4, edges: edges, labels: labels) == .text("0"))
        #expect(AnalyticsValue.bucket(1, edges: edges, labels: labels) == .text("1"))
        #expect(AnalyticsValue.bucket(9, edges: edges, labels: labels) == .text("2_9"))
        #expect(AnalyticsValue.bucket(10, edges: edges, labels: labels) == .text("10+"))
        #expect(AnalyticsValue.bucket(3, edges: [10, 2, 1], labels: labels) == .text("2_9"))
        // 数が合わなければ、ほかの帯の名前で送らずに既定の名前へ戻す
        #expect(AnalyticsValue.bucket(3, edges: edges, labels: ["a"]) == .text("2_9"))
    }

    @Test("帯は境界の下側に入る")
    func bucketsByLowerBound() {
        let edges = [1, 6, 16]
        #expect(AnalyticsValue.bucket(0, edges: edges) == .text("0"))
        #expect(AnalyticsValue.bucket(1, edges: edges) == .text("1_5"))
        #expect(AnalyticsValue.bucket(5, edges: edges) == .text("1_5"))
        #expect(AnalyticsValue.bucket(6, edges: edges) == .text("6_15"))
        #expect(AnalyticsValue.bucket(15, edges: edges) == .text("6_15"))
        #expect(AnalyticsValue.bucket(16, edges: edges) == .text("16_plus"))
        #expect(AnalyticsValue.bucket(9_999, edges: edges) == .text("16_plus"))
    }

    @Test("境界を昇順で渡さなくても同じ結果になる")
    func sortsEdges() {
        #expect(AnalyticsValue.bucket(7, edges: [16, 1, 6]) == .text("6_15"))
    }

    @Test("表示は送信先に依存しない形で決まる")
    func rendersDeterministically() {
        #expect(AnalyticsValue.text("solo_card").description == "solo_card")
        #expect(AnalyticsValue.count(3).description == "3")
        #expect(AnalyticsValue.flag(true).description == "true")
    }
}

@Suite("出来事の 1 行表現")
struct DebugLineTests {

    @Test("パラメータは鍵で整列する")
    func sortsParametersByKey() {
        let event = SampleEvent(parameters: ["source": .text("teaser"), "count": .count(2)])
        // Dictionary order changes between runs; unsorted, this could not be an expected value
        #expect(event.debugLine == "paywall_shown count=2 source=teaser")
    }

    @Test("パラメータが無ければ名前だけ")
    func rendersNameOnly() {
        #expect(SampleEvent(parameters: [:]).debugLine == "paywall_shown")
    }
}

private struct SampleEvent: AnalyticsEvent {
    var parameters: [String: AnalyticsValue]
    var name: String { "paywall_shown" }
    var kind: EventKind { .impression }
    var dedup: DedupScope { .always }
}
