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

    @Test("生成した出来事は sink を通って、受け口の JSON の形で届く")
    func travelsThroughTheSink() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "swift-analytics-tests").appending(path: UUID().uuidString)
        let bodies = Bodies()
        let sink = AnalyticsBatchSink(
            directory: directory,
            header: { ["v": .count(1), "catalog": .count(1), "install": .text("ins_0f")] },
            send: { body in
                bodies.append(body)
                return .delivered
            }
        )

        sink.track(TripEvent.tripCreated(source: .sampleCopy, nth: 1))
        sink.setUserProperty(TripUserProperty.plan(.trial))
        await sink.flush()

        let body = try #require(bodies.all.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["catalog"] as? Int == 1)
        #expect(json["plan"] as? String == "trial")
        let event = try #require((json["events"] as? [[String: Any]])?.first)
        #expect(event["name"] as? String == "trip_created")
        #expect(event["params"] as? [String: String] == ["source": "sample_copy", "nth": "1_1"])
    }
}

private final class Bodies: Sendable {
    private let state = OSAllocatedUnfairLock<[Data]>(initialState: [])
    var all: [Data] { state.withLock { $0 } }
    func append(_ data: Data) { state.withLock { $0.append(data) } }
}
