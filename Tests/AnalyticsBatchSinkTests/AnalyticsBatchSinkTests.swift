import AnalyticsCore
import Foundation
import os
import Testing
@testable import AnalyticsBatchSink

@Suite("溜めてまとめて送る")
struct AnalyticsBatchSinkTests {

    @Test("1件ごとに ID と時刻が付き、束の頭に header と属性が載る")
    func laysOutOneBatch() async throws {
        let rig = Rig()
        let sink = rig.sink(header: { ["install": .text("ins_1"), "v": .count(1)] })

        sink.setUserProperty(Property(name: "plan", value: "free"))
        sink.track(Event(name: "paywall_shown", parameters: ["placement": .text("settings"), "trial_eligible": .flag(true)]))
        let report = await sink.flush()

        #expect(report == FlushReport(status: .emptied, delivered: 1, discarded: 0, remaining: 0))
        let body = try #require(rig.sender.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["install"] as? String == "ins_1")
        #expect(json["v"] as? Int == 1)
        #expect(json["plan"] as? String == "free")
        let events = try #require(json["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events[0]["id"] as? String == "id-1")
        #expect(events[0]["name"] as? String == "paywall_shown")
        #expect(events[0]["at"] as? Double == Rig.start.timeIntervalSince1970)
        let params = try #require(events[0]["params"] as? [String: Any])
        #expect(params["placement"] as? String == "settings")
        #expect(params["trial_eligible"] as? Bool == true)
    }

    @Test("stamp の値はイベントの横に並び、sink 自身の鍵は上書きされない")
    func stampsEachEvent() async throws {
        let rig = Rig()
        let sink = rig.sink(stamp: { _, _ in ["sinceInstallDays": .count(0), "name": .text("spoofed")] })

        sink.track(Event(name: "app_opened"))
        await sink.flush()

        let event = try rig.firstEvent()
        #expect(event["sinceInstallDays"] as? Int == 0)
        #expect(event["name"] as? String == "app_opened")
    }

    @Test("1束は maxEvents まで。残りは同じ flush の次の束で送る")
    func cutsAtEventCount() async {
        let rig = Rig()
        let sink = rig.sink(policy: BatchPolicy(maxEvents: 3, flushThreshold: 1_000))

        for _ in 0..<7 { sink.track(Event(name: "tapped")) }
        let report = await sink.flush()

        #expect(report.delivered == 7)
        #expect(rig.sender.eventCounts == [3, 3, 1])
    }

    @Test("1束は maxBytes まで。本文はその大きさを超えない")
    func cutsAtBytes() async {
        let rig = Rig()
        let limit = 400
        let sink = rig.sink(policy: BatchPolicy(maxBytes: limit, flushThreshold: 1_000))

        for _ in 0..<10 { sink.track(Event(name: "block_seen", parameters: ["render_id": .text(String(repeating: "r", count: 40))])) }
        let report = await sink.flush()

        #expect(report.delivered == 10)
        #expect(rig.sender.bodies.count > 1)
        #expect(rig.sender.bodies.allSatisfy { $0.count <= limit })
    }

    @Test("1件だけで maxBytes を超えるものは捨て、後ろを止めない")
    func discardsOversizedEvent() async {
        let rig = Rig()
        let sink = rig.sink(policy: BatchPolicy(maxBytes: 200, flushThreshold: 1_000))

        sink.track(Event(name: "huge", parameters: ["blob": .text(String(repeating: "x", count: 500))]))
        sink.track(Event(name: "small"))
        let report = await sink.flush()

        #expect(report == FlushReport(status: .emptied, delivered: 1, discarded: 1, remaining: 0))
        #expect(rig.sender.names == [["small"]])
    }

    @Test("上限を超えたら古いものから消す")
    func dropsOldestPastCapacity() async {
        let rig = Rig()
        let sink = rig.sink(policy: BatchPolicy(capacity: 3, flushThreshold: 1_000))

        for index in 0..<5 { sink.track(Event(name: "e\(index)")) }
        #expect(sink.pendingCount == 3)
        await sink.flush()

        #expect(rig.sender.names == [["e2", "e3", "e4"]])
    }

    @Test("rejected の束は捨て、次の束に進む")
    func dropsRejectedBatch() async {
        let rig = Rig()
        rig.sender.script([.rejected, .delivered])
        let sink = rig.sink(policy: BatchPolicy(maxEvents: 2, flushThreshold: 1_000))

        for _ in 0..<4 { sink.track(Event(name: "tapped")) }
        let report = await sink.flush()

        #expect(report == FlushReport(status: .emptied, delivered: 2, discarded: 2, remaining: 0))
    }

    @Test("retryLater は束を残し、待ちが過ぎるまで送らない")
    func keepsBatchOnRetryLater() async {
        let rig = Rig()
        rig.sender.script([.retryLater(after: .seconds(120))])
        let sink = rig.sink()

        sink.track(Event(name: "tapped"))
        let first = await sink.flush()
        #expect(first == FlushReport(
            status: .deferred(until: Rig.start.addingTimeInterval(120)), delivered: 0, discarded: 0, remaining: 1
        ))

        rig.clock.advance(by: 90)
        let throttled = await sink.flush()
        #expect(throttled.status == .throttled(until: Rig.start.addingTimeInterval(120)))
        #expect(rig.sender.bodies.count == 1)

        rig.clock.advance(by: 30)
        let second = await sink.flush()
        #expect(second == FlushReport(status: .emptied, delivered: 1, discarded: 0, remaining: 0))
    }

    @Test("送る処理が throw したら（圏外）束を残し、minimumInterval の後に送り直す")
    func keepsBatchWhenUnreachable() async {
        let rig = Rig()
        rig.sender.failNext()
        let sink = rig.sink()

        sink.track(Event(name: "tapped"))
        let offline = await sink.flush()
        #expect(offline.status == .deferred(until: Rig.start.addingTimeInterval(60)))
        #expect(offline.remaining == 1)

        rig.clock.advance(by: 60)
        let online = await sink.flush()
        #expect(online.delivered == 1)
    }

    @Test("前の試みから minimumInterval の内は、成功の後でも送らない")
    func spacesAttempts() async {
        let rig = Rig()
        let sink = rig.sink()

        sink.track(Event(name: "a"))
        await sink.flush()
        rig.clock.advance(by: 59)
        sink.track(Event(name: "b"))
        let report = await sink.flush()

        #expect(report.status == .throttled(until: Rig.start.addingTimeInterval(60)))
        #expect(report.remaining == 1)
    }

    @Test("溜めた物は作り直した sink（次の起動）が読み、送る")
    func survivesRelaunch() async {
        let rig = Rig()
        let first = rig.sink()
        first.setUserProperty(Property(name: "plan", value: "trial"))
        first.track(Event(name: "app_opened"))
        await first.save()

        let relaunched = rig.sink()
        #expect(relaunched.pendingCount == 1)
        await relaunched.flush()

        #expect(rig.sender.names == [["app_opened"]])
        #expect(rig.sender.properties(at: 0)["plan"] as? String == "trial")
    }

    @Test("purge は溜めた物と属性とファイルを消す")
    func purgeErasesEverything() async {
        let rig = Rig()
        let sink = rig.sink()
        sink.setUserProperty(Property(name: "plan", value: "free"))
        sink.track(Event(name: "app_opened"))
        await sink.save()
        #expect(FileManager.default.fileExists(atPath: rig.spoolPath))

        await sink.purge()

        #expect(sink.pendingCount == 0)
        #expect(!FileManager.default.fileExists(atPath: rig.spoolPath))
        #expect(rig.sink().pendingCount == 0)
    }

    @Test("flushThreshold に達したら、呼ばなくても送る")
    func flushesAtThreshold() async throws {
        let rig = Rig()
        let sink = rig.sink(policy: BatchPolicy(flushThreshold: 3))

        for _ in 0..<3 { sink.track(Event(name: "tapped")) }

        try await waitUntil { rig.sender.bodies.count == 1 }
        #expect(rig.sender.eventCounts == [3])
    }

    @Test("鍵と時刻の単位を替えられる（ミリ秒・properties の入れ子）")
    func honoursFormat() async throws {
        let rig = Rig()
        let format = BatchFormat(timeKey: "occurredAt", time: .milliseconds, parametersKey: "properties", propertiesKey: "user")
        let sink = rig.sink(format: format)

        sink.setUserProperty(Property(name: "plan", value: "free"))
        sink.track(Event(name: "tapped", parameters: ["n": .count(2)]))
        await sink.flush()

        let event = try rig.firstEvent()
        #expect(event["occurredAt"] as? Int == Int(Rig.start.timeIntervalSince1970 * 1000))
        #expect((event["properties"] as? [String: Any])?["n"] as? Int == 2)
        #expect((rig.sender.properties(at: 0)["user"] as? [String: Any])?["plan"] as? String == "free")
    }

    @Test("同じ時に flush を2つ呼んでも、送るのは1つだけ")
    func oneFlushAtATime() async {
        let rig = Rig()
        rig.sender.holdNext()
        let sink = rig.sink()
        sink.track(Event(name: "tapped"))

        async let first = sink.flush()
        await rig.sender.waitUntilHeld()
        let second = await sink.flush()
        rig.sender.release()

        #expect(second.status == .busy)
        #expect(await first.delivered == 1)
    }
}

// MARK: - Fixtures

private struct Event: AnalyticsEvent {
    let name: String
    var parameters: [String: AnalyticsValue] = [:]
    var kind: EventKind { .interaction }
    var dedup: DedupScope { .always }
}

private struct Property: AnalyticsUserProperty {
    let name: String
    let value: String
}

private final class TestClock: Sendable {
    private let current = OSAllocatedUnfairLock(initialState: Rig.start)
    var now: Date { current.withLock { $0 } }
    func advance(by seconds: TimeInterval) { current.withLock { $0 += seconds } }
}

private struct Failure: Error {}

private final class Sender: Sendable {

    private struct State: Sendable {
        var bodies: [Data] = []
        var outcomes: [BatchOutcome] = []
        var failNext = false
        var hold: CheckedContinuation<Void, Never>?
        var holdNext = false
        var held = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var bodies: [Data] { state.withLock { $0.bodies } }

    var eventCounts: [Int] { bodies.map { Self.events(in: $0).count } }

    var names: [[String]] { bodies.map { Self.events(in: $0).compactMap { $0["name"] as? String } } }

    func properties(at index: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: bodies[index]) as? [String: Any]) ?? [:]
    }

    func script(_ outcomes: [BatchOutcome]) { state.withLock { $0.outcomes = outcomes } }
    func failNext() { state.withLock { $0.failNext = true } }
    func holdNext() { state.withLock { $0.holdNext = true } }

    func waitUntilHeld() async {
        while !state.withLock({ $0.held }) { await Task.yield() }
    }

    func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            defer { state.hold = nil }
            return state.hold
        }
        continuation?.resume()
    }

    func send(_ body: Data) async throws -> BatchOutcome {
        let holding = state.withLock { state -> Bool in
            defer { state.holdNext = false }
            return state.holdNext
        }
        if holding {
            await withCheckedContinuation { continuation in
                state.withLock { $0.hold = continuation; $0.held = true }
            }
        }
        return try state.withLock { state in
            if state.failNext {
                state.failNext = false
                throw Failure()
            }
            state.bodies.append(body)
            return state.outcomes.isEmpty ? .delivered : state.outcomes.removeFirst()
        }
    }

    private static func events(in body: Data) -> [[String: Any]] {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return json?["events"] as? [[String: Any]] ?? []
    }
}

private final class Rig: Sendable {

    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "swift-analytics-tests")
        .appending(path: UUID().uuidString)
    let clock = TestClock()
    let sender = Sender()
    private let ids = OSAllocatedUnfairLock(initialState: 0)

    var spoolPath: String { directory.appending(path: "events.json").path }

    func sink(
        policy: BatchPolicy = .standard,
        format: BatchFormat = .standard,
        header: @escaping @Sendable () async -> [String: AnalyticsValue] = { [:] },
        stamp: @escaping @Sendable (any AnalyticsEvent, Date) -> [String: AnalyticsValue] = { _, _ in [:] }
    ) -> AnalyticsBatchSink {
        let clock = clock
        let sender = sender
        let ids = ids
        return AnalyticsBatchSink(
            directory: directory,
            policy: policy,
            format: format,
            header: header,
            stamp: stamp,
            makeID: { "id-\(ids.withLock { $0 += 1; return $0 })" },
            now: { clock.now },
            send: { try await sender.send($0) }
        )
    }

    func firstEvent() throws -> [String: Any] {
        let body = try #require(sender.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(json["events"] as? [[String: Any]])
        return try #require(events.first)
    }
}

private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("timed out")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
