import AnalyticsCore
import Foundation
import SwiftUI

/// 直近に撃った計測を覚えておく箱。
///
/// ## なぜ端末の中に要るのか
///
/// 送信先のデバッグ画面は反映に間があり、`os.Logger` は Mac に繋がないと読めない。
/// そして **このアプリで一番確かめたい発火は、通知から戻ってきたときのもの** ——
/// Xcode を繋いだ状態では再現しにくく、再現できても数十秒かかる。
///
/// 送信の代わりではない。``AnalyticsCore/MultiplexAnalytics`` で本番送信と並べて使う。
@MainActor
@Observable
public final class AnalyticsLog {

    /// 1 行ぶんの記録。
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        /// 撃った時刻。
        public let at: Date
        /// 出来事の名前、または属性の名前。
        public let name: String
        /// `key=value` を並べたもの。無ければ空。
        public let detail: String
        /// 出来事の類。属性のときは nil。
        public let kind: EventKind?
        /// 数え方。属性のときは nil。
        public let dedup: DedupScope?

        /// 属性の記録か。
        public var isProperty: Bool { kind == nil }
    }

    public private(set) var entries: [Entry] = []

    private let limit: Int

    /// - Parameter limit: 覚えておく件数。古いものから捨てる
    public init(limit: Int = 200) {
        self.limit = limit
    }

    /// 出来事を積む。**新しい順に並ぶ。**
    public func record(_ event: any AnalyticsEvent) {
        let detail = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: "  ")
        append(
            Entry(at: Date(), name: event.name, detail: detail, kind: event.kind, dedup: event.dedup)
        )
    }

    /// 属性を積む。
    public func record(_ property: any AnalyticsUserProperty) {
        append(
            Entry(at: Date(), name: property.name, detail: property.value, kind: nil, dedup: nil)
        )
    }

    public func clear() {
        entries.removeAll()
    }

    /// ある名前が何回出たか。**「1 回のはずが 2 回出ている」を端末で見つけるための数字。**
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

/// 撃った計測を ``AnalyticsLog`` に控える送信口。
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

/// 直近の計測を出た順に並べる面。**開発メニューから開く。**
///
/// 見せているのは 3 つ。
///
/// - **何が出たか**（名前と引数）
/// - **どう数えるはずのものか**（種別と数え方）—— 期待とずれた瞬間に目で分かる
/// - **何回出たか** —— 2 回以上出ているものは色を変える。計測の事故はたいてい「出すぎ」
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
                // 空は「壊れている」ではなく「まだ撃っていない」。取り違えないよう言葉にしておく。
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
                    // **出すぎに気づけるようにする。** 1 回のはずのものが並んでいたら、
                    // それは配線の事故で、ダッシュボードでは見つからない。
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
