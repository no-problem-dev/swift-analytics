import AnalyticsCore
import Foundation
import os

/// A JSON value as it goes on the wire: no tags, so `3`, `"3"` and `true` read as themselves.
enum WireValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: WireValue])

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
        if let text = try? container.decode(String.self) { self = .string(text); return }
        self = .object(try container.decode([String: WireValue].self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(text): try container.encode(text)
        case let .int(count): try container.encode(count)
        case let .double(number): try container.encode(number)
        case let .bool(flag): try container.encode(flag)
        case let .object(object): try container.encode(object)
        }
    }
}

/// One occurrence as kept on the device, before it is laid out in a batch.
struct SpooledEvent: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let at: Double
    let parameters: [String: WireValue]
    let stamp: [String: WireValue]
}

/// Everything the sink holds, behind one lock.
struct SpoolState: Sendable {
    var events: [SpooledEvent] = []
    var properties: [String: WireValue] = [:]
    /// Bumped on every change, so a write that is already current can be skipped.
    var generation = 0
    var isFlushing = false
    var isAutoFlushPending = false
    var notBefore: Date?

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

    private struct Contents: Codable {
        var format = 1
        var events: [SpooledEvent]
        var properties: [String: WireValue]
    }

    let url: URL
    private var writtenGeneration: Int?

    init(directory: URL) {
        url = directory.appending(path: "events.json")
    }

    nonisolated func load() -> (events: [SpooledEvent], properties: [String: WireValue]) {
        guard let data = try? Data(contentsOf: url),
              let contents = try? JSONDecoder().decode(Contents.self, from: data)
        else { return ([], [:]) }
        return (contents.events, contents.properties)
    }

    func persist(from state: OSAllocatedUnfairLock<SpoolState>) {
        let snapshot = state.withLock { $0 }
        guard snapshot.generation != writtenGeneration else { return }
        do {
            if snapshot.events.isEmpty && snapshot.properties.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                let contents = Contents(events: snapshot.events, properties: snapshot.properties)
                try JSONEncoder().encode(contents).write(to: url, options: .atomic)
            }
            writtenGeneration = snapshot.generation
        } catch {
            // Left for the next write. The events are still in memory and go out with the next
            // flush; only a relaunch before then loses them.
        }
    }
}

/// Lays events out as one request body, measuring as it goes.
///
/// The body is spliced from separately encoded pieces rather than encoded whole, so the size of
/// each event is known exactly and a batch can be cut at ``BatchPolicy/maxBytes`` without encoding
/// it again for every event added.
struct BatchLayout {

    let format: BatchFormat
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

    func header(
        fields: [String: AnalyticsValue],
        properties: [String: WireValue]
    ) -> [String: WireValue] {
        var top: [String: WireValue] = [:]
        if let key = format.propertiesKey {
            if !properties.isEmpty { top[key] = .object(properties) }
        } else {
            top.merge(properties) { _, new in new }
        }
        top.merge(fields.mapValues(WireValue.init)) { _, new in new }
        top[format.eventsKey] = nil
        return top
    }

    func record(_ event: SpooledEvent) -> [String: WireValue] {
        var record = event.stamp
        record[format.idKey] = .string(event.id)
        record[format.nameKey] = .string(event.name)
        switch format.time {
        case .seconds: record[format.timeKey] = .double(event.at)
        case .milliseconds: record[format.timeKey] = .int(Int((event.at * 1000).rounded()))
        }
        record[format.parametersKey] = .object(event.parameters)
        return record
    }

    func batch(of candidates: [SpooledEvent], header: [String: WireValue]) throws -> Batch {
        let headerData = try Self.encoder.encode(header)
        let eventsKey = try Self.encoder.encode(format.eventsKey)
        var opening = Data(headerData.dropLast())
        if !header.isEmpty { opening.append(UInt8(ascii: ",")) }
        opening.append(eventsKey)
        opening.append(contentsOf: Array(":[".utf8))
        let closing = Data("]}".utf8)

        var size = opening.count + closing.count
        var pieces: [Data] = []
        var included: [String] = []
        var oversized: [String] = []

        for event in candidates.prefix(policy.maxEvents) {
            let piece = try Self.encoder.encode(record(event))
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
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
