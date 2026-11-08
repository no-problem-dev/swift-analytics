import AnalyticsCore
import Foundation
import os
import Testing
@testable import AnalyticsBatchSink

@Suite("溜めてまとめて送る")
struct AnalyticsBatchSinkTests {

    @Test("束は ENVELOPE.md の形で届く（頭の項目・ミリ秒・id・props）")
    func laysOutTheEnvelope() async throws {
        let rig = Rig()
        rig.uid.withLock { $0 = "uid_1" }
        let sink = rig.sink()

        sink.track(Event(name: "paywall_shown", parameters: ["source": .text("onboarding"), "nth": .text("1_1")]))
        rig.clock.advance(by: 2)
        let report = await sink.flush()

        #expect(report == FlushReport(status: .emptied, delivered: 1, discarded: 0, remaining: 0))
        let json = try rig.sender.json(at: 0)
        #expect(Set(json.keys) == [
            "schema_version", "app", "install_id", "uid", "app_version", "build", "channel", "lang", "region",
            "sent_at", "events",
        ])
        #expect(json["schema_version"] as? Int == 1)
        #expect(json["app"] as? String == "kotoakari")
        #expect(json["install_id"] as? String == "8c1f0000-0000-4000-8000-000000000000")
        #expect(json["uid"] as? String == "uid_1")
        #expect(json["app_version"] as? String == "1.2.0")
        #expect(json["build"] as? String == "45")
        #expect(json["channel"] as? String == "testflight")
        #expect(json["lang"] as? String == "ja")
        #expect(json["region"] as? String == "JP")
        #expect(json["sent_at"] as? Int == Rig.startMilliseconds + 2_000)
        let events = try #require(json["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(Set(events[0].keys) == ["id", "name", "occurred_at", "props"])
        #expect(events[0]["id"] as? String == "id-1")
        #expect(events[0]["name"] as? String == "paywall_shown")
        #expect(events[0]["occurred_at"] as? Int == Rig.startMilliseconds)
        #expect(events[0]["props"] as? [String: String] == ["source": "onboarding", "nth": "1_1"])
    }

    @Test("POST で JSON を送り、authorize の項目をヘッダに載せる")
    func postsWithAuthorization() async throws {
        let rig = Rig()
        let sink = rig.sink(authorize: { ["Authorization": "Bearer t0k"] })

        sink.track(Event(name: "tapped"))
        await sink.flush()

        let request = try #require(rig.sender.requests.first)
        #expect(request.url == Rig.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test("authorize が throw したら束を残す（トークンが無いだけで捨てない）")
    func keepsBatchWhenAuthorizationFails() async {
        let rig = Rig()
        let sink = rig.sink(authorize: { throw Failure() })

        sink.track(Event(name: "tapped"))
        let report = await sink.flush()

        #expect(report.status == .deferred(until: Rig.start.addingTimeInterval(60)))
        #expect(report.remaining == 1)
        #expect(rig.sender.requests.isEmpty)
    }

    @Test("uid が無ければ uid の鍵を書かない")
    func omitsMissingUID() async throws {
        let rig = Rig()
        let sink = rig.sink()

        sink.track(Event(name: "tapped"))
        await sink.flush()

        #expect(try rig.sender.json(at: 0)["uid"] == nil)
    }

    @Test("版・ビルド・uid が違う出来事は別の束で送る（頭はそれが起きたときの値）")
    func splitsBatchesByOrigin() async throws {
        let rig = Rig()
        let sink = rig.sink()

        sink.track(Event(name: "before_sign_in"))
        rig.uid.withLock { $0 = "uid_1" }
        sink.track(Event(name: "after_sign_in"))
        sink.track(Event(name: "still_signed_in"))
        await sink.flush()

        #expect(rig.sender.names == [["before_sign_in"], ["after_sign_in", "still_signed_in"]])
        #expect(try rig.sender.json(at: 0)["uid"] == nil)
        #expect(try rig.sender.json(at: 1)["uid"] as? String == "uid_1")
    }

    @Test("応答の読み方は固定（2xx 届いた・401/429/5xx 残す・その他の 4xx 捨てる）")
    func readsResponses() {
        #expect(BatchOutcome(status: 200, retryAfter: nil) == .delivered)
        #expect(BatchOutcome(status: 204, retryAfter: nil) == .delivered)
        #expect(BatchOutcome(status: 400, retryAfter: nil) == .rejected)
        #expect(BatchOutcome(status: 413, retryAfter: nil) == .rejected)
        #expect(BatchOutcome(status: 401, retryAfter: nil) == .retryLater(after: nil))
        #expect(BatchOutcome(status: 429, retryAfter: "120") == .retryLater(after: .seconds(120)))
        #expect(BatchOutcome(status: 503, retryAfter: "soon") == .retryLater(after: nil))
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
        let sink = rig.sink(policy: BatchPolicy(maxBytes: 500, flushThreshold: 1_000))

        sink.track(Event(name: "huge", parameters: ["blob": .text(String(repeating: "x", count: 600))]))
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
        rig.sender.script([400, 200])
        let sink = rig.sink(policy: BatchPolicy(maxEvents: 2, flushThreshold: 1_000))

        for _ in 0..<4 { sink.track(Event(name: "tapped")) }
        let report = await sink.flush()

        #expect(report == FlushReport(status: .emptied, delivered: 2, discarded: 2, remaining: 0))
    }

    @Test("retryLater は束を残し、待ちが過ぎるまで送らない")
    func keepsBatchOnRetryLater() async {
        let rig = Rig()
        rig.sender.script([429], retryAfter: "120")
        let sink = rig.sink()

        sink.track(Event(name: "tapped"))
        let first = await sink.flush()
        #expect(first == FlushReport(
            status: .deferred(until: Rig.start.addingTimeInterval(120)), delivered: 0, discarded: 0, remaining: 1
        ))

        rig.clock.advance(by: 90)
        let throttled = await sink.flush()
        #expect(throttled.status == .throttled(until: Rig.start.addingTimeInterval(120)))
        #expect(rig.sender.requests.count == 1)

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

    @Test("裏に回るときの flush(ignoringInterval: true) は間隔を待たずに送る")
    func backgroundFlushSkipsTheInterval() async {
        let rig = Rig()
        let sink = rig.sink()

        sink.track(Event(name: "a"))
        await sink.flush()
        rig.clock.advance(by: 5)
        sink.track(Event(name: "b"))
        let report = await sink.flush(ignoringInterval: true)

        #expect(report == FlushReport(status: .emptied, delivered: 1, discarded: 0, remaining: 0))
        #expect(rig.sender.names == [["a"], ["b"]])
    }

    @Test("間隔を無視しても、受け手が頼んだ待ち（Retry-After）は守る")
    func backgroundFlushHonoursRetryAfter() async {
        let rig = Rig()
        rig.sender.script([429], retryAfter: "120")
        let sink = rig.sink()

        sink.track(Event(name: "tapped"))
        await sink.flush()
        rig.clock.advance(by: 10)
        let report = await sink.flush(ignoringInterval: true)

        #expect(report.status == .throttled(until: Rig.start.addingTimeInterval(120)))
        #expect(rig.sender.requests.count == 1)
    }

    @Test("occurred(at:) で作った出来事は、その時刻で occurred_at に載る")
    func usesTheTimeTheEventCarries() async throws {
        let rig = Rig()
        let sink = rig.sink()

        let earlier = Rig.start.addingTimeInterval(-3)
        sink.track(Event(name: "onboarding_step").occurred(at: earlier))
        sink.track(Event(name: "now"))
        await sink.flush()

        let events = try #require(try rig.sender.json(at: 0)["events"] as? [[String: Any]])
        #expect(events[0]["name"] as? String == "onboarding_step")
        #expect(events[0]["occurred_at"] as? Int == Rig.startMilliseconds - 3_000)
        #expect(events[1]["occurred_at"] as? Int == Rig.startMilliseconds)
    }

    @Test("lang は BCP 47 の言語の札（簡体字と繁体字を分ける・地域は入れない）")
    func languageTags() {
        let tag = { EnvelopeContext.languageTag(of: Locale(identifier: $0)) }
        #expect(tag("ja_JP") == "ja")
        #expect(tag("en_US") == "en")
        #expect(tag("pt_BR") == "pt")
        #expect(tag("zh-Hans_CN") == "zh-Hans")
        #expect(tag("zh-Hant_TW") == "zh-Hant")
        #expect(tag("zh_TW") == "zh-Hant")
        #expect(tag("sr-Latn_RS") == "sr-Latn")
    }

    @Test("溜めた物は作り直した sink（次の起動）が読み、送る")
    func survivesRelaunch() async throws {
        let rig = Rig()
        let first = rig.sink()
        first.track(Event(name: "app_opened"))
        await first.save()

        rig.version.withLock { $0 = "1.3.0" }
        let relaunched = rig.sink()
        #expect(relaunched.pendingCount == 1)
        await relaunched.flush()

        #expect(rig.sender.names == [["app_opened"]])
        // 起きたときの版で送る（更新の後に送っても、前の版の出来事は前の版）
        #expect(try rig.sender.json(at: 0)["app_version"] as? String == "1.2.0")
    }

    @Test("0.2 の形のファイルは読まない")
    func ignoresOldSpoolFormat() throws {
        let rig = Rig()
        try FileManager.default.createDirectory(at: rig.directory, withIntermediateDirectories: true)
        let old = #"{"format":1,"events":[{"id":"a","name":"x","at":1.0,"parameters":{},"stamp":{}}],"properties":{}}"#
        try Data(old.utf8).write(to: URL(filePath: rig.spoolPath))

        #expect(rig.sink().pendingCount == 0)
    }

    @Test("属性は送らない（封筒に場所が無い）")
    func ignoresProperties() async throws {
        let rig = Rig()
        let sink = rig.sink()
        sink.setUserProperty(Property(name: "plan", value: "free"))
        sink.track(Event(name: "tapped"))
        await sink.flush()

        #expect(try rig.sender.json(at: 0)["plan"] == nil)
    }

    @Test("purge は溜めた物とファイルを消す")
    func purgeErasesEverything() async {
        let rig = Rig()
        let sink = rig.sink()
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

        try await waitUntil { rig.sender.requests.count == 1 }
        #expect(rig.sender.eventCounts == [3])
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
        var requests: [URLRequest] = []
        var statuses: [Int] = []
        var retryAfter: String?
        var failNext = false
        var hold: CheckedContinuation<Void, Never>?
        var holdNext = false
        var held = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var requests: [URLRequest] { state.withLock { $0.requests } }

    var bodies: [Data] { requests.compactMap(\.httpBody) }

    var eventCounts: [Int] { bodies.map { Self.events(in: $0).count } }

    var names: [[String]] { bodies.map { Self.events(in: $0).compactMap { $0["name"] as? String } } }

    func json(at index: Int) throws -> [String: Any] {
        let body = try #require(bodies.indices.contains(index) ? bodies[index] : nil)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func script(_ statuses: [Int], retryAfter: String? = nil) {
        state.withLock { $0.statuses = statuses; $0.retryAfter = retryAfter }
    }
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

    func perform(_ request: URLRequest) async throws -> HTTPURLResponse {
        let holding = state.withLock { state -> Bool in
            defer { state.holdNext = false }
            return state.holdNext
        }
        if holding {
            await withCheckedContinuation { continuation in
                state.withLock { $0.hold = continuation; $0.held = true }
            }
        }
        let (status, retryAfter) = try state.withLock { state -> (Int, String?) in
            if state.failNext {
                state.failNext = false
                throw Failure()
            }
            state.requests.append(request)
            return (state.statuses.isEmpty ? 200 : state.statuses.removeFirst(), state.retryAfter)
        }
        let headers = retryAfter.map { ["Retry-After": $0] }
        return HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private static func events(in body: Data) -> [[String: Any]] {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return json?["events"] as? [[String: Any]] ?? []
    }
}

private final class Rig: Sendable {

    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let startMilliseconds = 1_790_000_000_000
    static let endpoint = URL(string: "https://example.com/v1/events")!

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "swift-analytics-tests")
        .appending(path: UUID().uuidString)
    let clock = TestClock()
    let sender = Sender()
    let uid = OSAllocatedUnfairLock<String?>(initialState: nil)
    let version = OSAllocatedUnfairLock(initialState: "1.2.0")
    private let ids = OSAllocatedUnfairLock(initialState: 0)

    var spoolPath: String { directory.appending(path: "events.json").path }

    func sink(
        policy: BatchPolicy = .standard,
        authorize: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) -> AnalyticsBatchSink {
        let clock = clock
        let sender = sender
        let ids = ids
        let uid = uid
        let version = version
        return AnalyticsBatchSink(
            app: "kotoakari",
            endpoint: Self.endpoint,
            authorize: authorize,
            uid: { uid.withLock { $0 } },
            directory: directory,
            policy: policy,
            context: {
                EnvelopeContext(
                    installID: "8c1f0000-0000-4000-8000-000000000000",
                    appVersion: version.withLock { $0 }, build: "45", channel: .testflight, lang: "ja", region: "JP"
                )
            },
            transport: BatchTransport { try await sender.perform($0) },
            makeID: { "id-\(ids.withLock { $0 += 1; return $0 })" },
            now: { clock.now }
        )
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
