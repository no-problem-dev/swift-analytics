import AnalyticsCore
import Foundation
import os

/// A JSON value as it goes on the wire: no tags, so `3`, `"3"` and `true` read as themselves.
///
/// Flat on purpose — `props` holds strings, numbers, and booleans only (`ENVELOPE.md`).
enum WireValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(_ value: AnalyticsValue) {
        switch value {
        case let .text(text): self = .string(text)
        case let .count(count): self = .int(count)
        case let .number(number): self = .double(number)
        case let .flag(flag): self = .bool(flag)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) { self = .bool(flag); return }
        if let count = try? container.decode(Int.self) { self = .int(count); return }
        if let number = try? container.decode(Double.self) { self = .double(number); return }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(text): try container.encode(text)
        case let .int(count): try container.encode(count)
        case let .double(number): try container.encode(number)
        case let .bool(flag): try container.encode(flag)
        }
    }
}

/// One occurrence as kept on the device, before it is laid out in a batch.
///
/// The app version, build, and uid are the ones **when it happened**. A batch carries one of each
/// in its head, so events that differ in them go in separate batches.
struct SpooledEvent: Codable, Sendable, Equatable {
    let id: String
    let name: String
    /// Milliseconds since 1970, UTC.
    let occurredAt: Int
    let props: [String: WireValue]
    let appVersion: String
    let build: String
    let uid: String?

    struct Origin: Equatable {
        let appVersion: String
        let build: String
        let uid: String?
    }

    var origin: Origin { Origin(appVersion: appVersion, build: build, uid: uid) }
}

/// Everything the sink holds, behind one lock.
struct SpoolState: Sendable {
    var events: [SpooledEvent] = []
    /// Bumped on every change, so a write that is already current can be skipped.
    var generation = 0
    var isFlushing = false
    var isAutoFlushPending = false
    /// No attempt before this: ``BatchPolicy/minimumInterval`` after the last one.
    var notBefore: Date?
    /// No attempt before this either, because the receiver said so (`Retry-After`, `429`, `5xx`).
    /// Kept apart so that ``AnalyticsBatchSink/flush(ignoringInterval:)`` still honours it.
    var receiverNotBefore: Date?

    mutating func trim(to capacity: Int) {
        guard events.count > capacity else { return }
        events.removeFirst(events.count - capacity)
    }
}

/// The file the spool lives in.
///
/// An actor so writes never interleave. Each write reads the state as it is **when the write
/// runs**, not when it was asked for, so whichever write runs last leaves the latest state on
/// disk however the requests were ordered.
actor SpoolFile {

    /// What is on disk. A file in another format (0.2 wrote `format: 1`) is not read: its events
    /// were laid out for a different envelope.
    private struct Contents: Codable {
        static let currentFormat = 2
        var format = Contents.currentFormat
        var events: [SpooledEvent]
    }

    let url: URL
    private var writtenGeneration: Int?

    init(directory: URL) {
        url = directory.appending(path: "events.json")
    }

    nonisolated func load() -> [SpooledEvent] {
        guard let data = try? Data(contentsOf: url),
              let contents = try? JSONDecoder().decode(Contents.self, from: data),
              contents.format == Contents.currentFormat
        else { return [] }
        return contents.events
    }

    func persist(from state: OSAllocatedUnfairLock<SpoolState>) {
        let snapshot = state.withLock { $0 }
        guard snapshot.generation != writtenGeneration else { return }
        do {
            if snapshot.events.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                let contents = Contents(events: snapshot.events)
                try JSONEncoder().encode(contents).write(to: url, options: .atomic)
            }
            writtenGeneration = snapshot.generation
        } catch {
            // Left for the next write. The events are still in memory and go out with the next
            // flush; only a relaunch before then loses them.
        }
    }
}

/// Lays events out as one request body in the fixed envelope, measuring as it goes.
///
/// The body is spliced from separately encoded pieces rather than encoded whole, so the size of
/// each event is known exactly and a batch can be cut at ``BatchPolicy/maxBytes`` without encoding
/// it again for every event added.
struct BatchLayout {

    /// `schema_version` in the head. Raise it when the envelope's shape changes.
    static let schemaVersion = 1

    let policy: BatchPolicy

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    struct Batch {
        var body: Data
        var included: [String]
        var oversized: [String]
    }

    func header(app: String, context: EnvelopeContext, origin: SpooledEvent.Origin, sentAt: Date) -> [String: WireValue] {
        var top: [String: WireValue] = [
            "schema_version": .int(Self.schemaVersion),
            "app": .string(app),
            "install_id": .string(context.installID),
            "app_version": .string(origin.appVersion),
            "build": .string(origin.build),
            "channel": .string(context.channel.rawValue),
            "lang": .string(context.lang),
            "region": .string(context.region),
            "sent_at": .int(Self.milliseconds(sentAt)),
        ]
        if let uid = origin.uid { top["uid"] = .string(uid) }
        return top
    }

    private struct Record: Encodable {
        let id: String
        let name: String
        let occurred_at: Int
        let props: [String: WireValue]
    }

    func batch(of candidates: [SpooledEvent], header: [String: WireValue]) throws -> Batch {
        let headerData = try Self.encoder.encode(header)
        var opening = Data(headerData.dropLast())
        opening.append(contentsOf: Array(#","events":["#.utf8))
        let closing = Data("]}".utf8)

        var size = opening.count + closing.count
        var pieces: [Data] = []
        var included: [String] = []
        var oversized: [String] = []

        for event in candidates.prefix(policy.maxEvents) {
            let piece = try Self.encoder.encode(
                Record(id: event.id, name: event.name, occurred_at: event.occurredAt, props: event.props)
            )
            let separator = pieces.isEmpty ? 0 : 1
            if size + separator + piece.count > policy.maxBytes {
                if pieces.isEmpty, opening.count + closing.count + piece.count > policy.maxBytes {
                    oversized.append(event.id)
                    continue
                }
                break
            }
            size += separator + piece.count
            pieces.append(piece)
            included.append(event.id)
        }

        var body = opening
        for (index, piece) in pieces.enumerated() {
            if index > 0 { body.append(UInt8(ascii: ",")) }
            body.append(piece)
        }
        body.append(closing)
        return Batch(body: body, included: included, oversized: oversized)
    }

    static func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
