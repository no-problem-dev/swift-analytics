import AnalyticsCore
import Foundation
import SwiftUI

/// An in-memory record of what was measured most recently, readable on the device itself.
///
/// ## Why it has to be on the device
///
/// A destination's debug view lags behind, and `os.Logger` cannot be read without a Mac attached.
/// And **the firing this app most wants to check is the one that happens on the way back from a
/// notification** — hard to reproduce with Xcode attached, and tens of seconds each time when it
/// can be.
///
/// It does not replace sending. Put it alongside the real client with
/// ``AnalyticsCore/MultiplexAnalytics``.
@MainActor
@Observable
public final class AnalyticsLog {

    /// One recorded line.
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        /// When the log took it in, which is a moment after the client was called.
        public let at: Date
        /// Name of the occurrence, or of the property.
        public let name: String
        /// Parameters laid out as `key=value`, or empty when there were none.
        public let detail: String
        /// Sort of occurrence, or nil when this line records a property.
        public let kind: EventKind?
        /// Counting rule, or nil when this line records a property.
        public let dedup: DedupScope?

        /// Whether this line records a property, which is also why it carries no sort or rule.
        public var isProperty: Bool { kind == nil }
    }

    public private(set) var entries: [Entry] = []

    private let limit: Int

    /// - Parameter limit: How many lines to keep; the oldest are dropped once it is exceeded
    public init(limit: Int = 200) {
        self.limit = limit
    }

    /// Takes in one occurrence. **Newest first.**
    ///
    /// Nothing is thinned out here: an occurrence that arrived twice appears twice, which is the
    /// whole point of reading this on the device. Parameters are laid out sorted by key.
    public func record(_ event: any AnalyticsEvent) {
        let detail = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: "  ")
        append(
            Entry(at: Date(), name: event.name, detail: detail, kind: event.kind, dedup: event.dedup)
        )
    }

    /// Takes in one property, with its value standing in for the parameters.
    public func record(_ property: any AnalyticsUserProperty) {
        append(
            Entry(at: Date(), name: property.name, detail: property.value, kind: nil, dedup: nil)
        )
    }

    public func clear() {
        entries.removeAll()
    }

    /// How many of the lines still held carry this name.
    ///
    /// **The number that catches "fired twice where once was meant" on the device.** It reaches
    /// back only as far as the lines that have not yet been dropped.
    public func count(of name: String) -> Int {
        entries.filter { $0.name == name }.count
    }

    private func append(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }
}

/// A client that files what was measured into an ``AnalyticsLog`` instead of sending it out.
///
/// Filing hops to the main actor, so a line shows up a moment after the call rather than during
/// it.
public struct LoggingAnalytics: AnalyticsClient {

    private let log: AnalyticsLog

    public init(log: AnalyticsLog) {
        self.log = log
    }

    public func track(_ event: any AnalyticsEvent) {
        Task { @MainActor in log.record(event) }
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        Task { @MainActor in log.record(property) }
    }
}

/// A screen listing recent measurements in the order they fired. **Opened from a developer menu.**
///
/// It shows three things.
///
/// - **What came out** (name and parameters)
/// - **How it was meant to be counted** (sort and rule) — a departure from the intent is visible
///   the moment it happens
/// - **How many times it came out** — anything past one is coloured, because measurement
///   accidents are usually one too many
public struct AnalyticsLogViewer: View {

    private let log: AnalyticsLog

    @State private var query = ""
    @State private var showsPropertiesOnly = false

    public init(log: AnalyticsLog) {
        self.log = log
    }

    public var body: some View {
        List {
            if log.entries.isEmpty {
                // Empty means "nothing has fired yet", not "this is broken". Say so, so the two
                // are not mistaken for each other.
                ContentUnavailableView(
                    "まだ何も撃っていません",
                    systemImage: "waveform",
                    description: Text("画面を操作すると、出た順にここへ並びます。")
                )
            } else {
                ForEach(visible) { entry in
                    row(entry)
                }
            }
        }
        .searchable(text: $query, prompt: "名前で絞る")
        .navigationTitle("計測ログ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("属性だけ", isOn: $showsPropertiesOnly)
                    Button("消す", role: .destructive) { log.clear() }
                        .disabled(log.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var visible: [AnalyticsLog.Entry] {
        log.entries.filter { entry in
            if showsPropertiesOnly, !entry.isProperty { return false }
            guard !query.isEmpty else { return true }
            return entry.name.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func row(_ entry: AnalyticsLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.name)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                let count = log.count(of: entry.name)
                if count > 1 {
                    // **Make firing too often noticeable.** A run of something meant to fire once
                    // is a wiring accident, and the dashboard will not find it.
                    Text("×\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Text(entry.at, format: .dateTime.hour().minute().second())
                if let kind = entry.kind, let dedup = entry.dedup {
                    Text("\(kind.rawValue) / \(dedup.rawValue)")
                } else {
                    Text("属性")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
