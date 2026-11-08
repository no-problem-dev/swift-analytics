import AnalyticsCore
import Foundation
import os
import Testing
@testable import AnalyticsBatchSink

/// What `Scripts/analytics-gen.py` writes for `dialect: first_party` compiles, closes `token`
/// values over their shape, and travels through the sink as the receiver expects.
///
/// `Generated/TripAnalytics.swift` is generated from `Schema/example-first-party.yaml`.
@Suite("自前の受け口のカタログ")
struct FirstPartyCatalogTests {

    @Test("token は形に合うものだけを作れる")
    func tokensAreClosedOverTheirShape() {
        #expect(TripEvent.RenderId("r_01J9ABCD") != nil)
        #expect(TripEvent.RenderId("short") == nil)
        #expect(TripEvent.RenderId("has space in it") == nil)
        #expect(TripEvent.RenderId(String(repeating: "a", count: 41)) == nil)
        #expect(TripEvent.BlockKey("place:ChIJ123") != nil)
        #expect(TripEvent.BlockKey("ChIJ123") == nil)
        #expect(TripEvent.BlockKey("place:" + String(repeating: "a", count: 59)) == nil)
    }

    @Test("token は文字列として、bucket は帯として載る")
    func carriesTokensAndBuckets() throws {
        let renderID = try #require(TripEvent.RenderId("r_01J9ABCD"))
        let blockKey = try #require(TripEvent.BlockKey("place:ChIJ123"))
        let event = TripEvent.blockSeen(renderId: renderID, blockKey: blockKey, position: 4)

        #expect(event.parameters == [
            "render_id": .text("r_01J9ABCD"),
            "block_key": .text("place:ChIJ123"),
            "position": .text("3_4"),
        ])
        #expect(event.kind == .impression)
    }

    @Test("生成した出来事は sink を通って、封筒の props に載る")
    func travelsThroughTheSink() async throws {
        let bodies = Bodies()
        let sink = makeSink(bodies)

        sink.track(TripEvent.tripCreated(source: .sampleCopy, nth: 1))
        await sink.flush()

        let event = try #require(try bodies.events(at: 0).first)
        #expect(event["name"] as? String == "trip_created")
        #expect(event["props"] as? [String: String] == ["source": "sample_copy", "nth": "1_1"])
    }
}

/// What the generator writes for a catalog that includes the common one compiles, and its events
/// travel in the envelope with the names and values the receiver's TypeScript expects.
///
/// `Generated/JournalAnalytics.swift` is generated from `Schema/example-common.yaml`.
@Suite("共通カタログを取り込んだカタログ")
struct CommonCatalogTests {

    @Test("extend で足した値と引数が、共通の型に入る")
    func extendedValuesAreInTheSharedTypes() throws {
        #expect(JournalEvent.ScreenName.allCases.map(\.rawValue) == ["onboarding", "paywall", "settings", "whats_new", "home", "entry"])
        #expect(JournalEvent.PaywallSource.entryLimit.rawValue == "entry_limit")
        let pwID = try #require(JournalEvent.PwId("0a1b2c3d"))
        let event = JournalEvent.paywallShown(source: .entryLimit, pwId: pwID, nth: 2, variant: .cards)
        #expect(event.parameters == [
            "source": .text("entry_limit"), "pw_id": .text("0a1b2c3d"), "nth": .text("2_2"), "variant": .text("cards"),
        ])
        #expect(event.kind == .impression)
    }

    @Test("任意の引数は省いて呼べ、nil なら props に載らない")
    func optionalParameterIsLeftOut() throws {
        let pwID = try #require(JournalEvent.PwId("0a1b2c3d"))
        let dismissed = JournalEvent.paywallClosed(source: .settings, pwId: pwID, result: .dismissed, via: .closeButton, openS: 4)
        #expect(dismissed.parameters == [
            "source": .text("settings"), "pw_id": .text("0a1b2c3d"), "result": .text("dismissed"),
            "via": .text("close_button"), "open_s": .count(4),
        ])
        let purchased = JournalEvent.paywallClosed(source: .settings, pwId: pwID, result: .purchased, via: .auto, product: .yearly, openS: 9)
        #expect(purchased.parameters["product"] == .text("yearly"))
    }

    @Test("labels を書いた bucket はその名前で載る")
    func labelledBucket() {
        let event = JournalEvent.entrySaved(screen: .home, words: 3, streak: 12)
        #expect(event.parameters["streak"] == .text("10+"))
        #expect(event.parameters["words"] == .text("1_49"))
        #expect(JournalEvent.entrySaved(screen: .home, words: 3).parameters["streak"] == nil)
    }

    @Test("お知らせの版の token は「1.2」「1.2.3」の形だけを通す")
    func releaseTokenFollowsItsPattern() {
        #expect(JournalEvent.Release("1.2") != nil)
        #expect(JournalEvent.Release("1.2.3") != nil)
        #expect(JournalEvent.Release("1") == nil)
        #expect(JournalEvent.Release("1x2") == nil)
    }

    @Test("共通の出来事も、パッケージが送る出来事も封筒に載る")
    func travelsInTheEnvelope() async throws {
        let bodies = Bodies()
        let sink = makeSink(bodies)
        let pwID = try #require(JournalEvent.PwId("deadbeef"))

        sink.track(JournalEvent.purchaseCompleted(source: .onboarding, pwId: pwID, product: .yearly))
        sink.track(CommonEvent.firstOpen(kind: .fresh))
        await sink.flush()

        let events = try bodies.events(at: 0)
        #expect(events.map { $0["name"] as? String } == ["purchase_completed", "first_open"])
        #expect(events[0]["props"] as? [String: String] == ["source": "onboarding", "pw_id": "deadbeef", "product": "yearly"])
        #expect(events[1]["props"] as? [String: String] == ["kind": "fresh"])
    }
}

private func makeSink(_ bodies: Bodies) -> AnalyticsBatchSink {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "swift-analytics-tests").appending(path: UUID().uuidString)
    return AnalyticsBatchSink(
        app: "trip",
        endpoint: URL(string: "https://example.com/events")!,
        directory: directory,
        context: { EnvelopeContext(installID: "i", appVersion: "1.0", build: "1", channel: .debug, lang: "en", region: "US") },
        transport: BatchTransport { request in
            bodies.append(request.httpBody ?? Data())
            return HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        }
    )
}

private final class Bodies: Sendable {
    private let state = OSAllocatedUnfairLock<[Data]>(initialState: [])
    var all: [Data] { state.withLock { $0 } }
    func append(_ data: Data) { state.withLock { $0.append(data) } }

    func events(at index: Int) throws -> [[String: Any]] {
        let body = try #require(all.indices.contains(index) ? all[index] : nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(json["events"] as? [[String: Any]])
    }
}
