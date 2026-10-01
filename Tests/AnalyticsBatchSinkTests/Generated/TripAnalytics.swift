// このファイルは analytics-gen.py が書き出しています。手で編集しないでください。
//
// 正典は analytics.yaml。**先にそちらを直してから生成する。**

import AnalyticsCore

/// このアプリが送れる出来事の全部。
///
/// 増やすときは analytics.yaml を直してから生成し直す。
public enum TripEvent: AnalyticsEvent {

    /// アプリを開いた
    case appOpened(firstLaunch: Bool, entry: Entry)

    /// 旅行の作成が終わった
    case tripCreated(source: Source, nth: Int)

    /// 候補のブロックが半分以上、1 秒見えた
    case blockSeen(renderId: RenderId, blockKey: BlockKey, position: Int)

    /// 相談の答えの流しが終わった
    case consultAnswerFinished(result: AnswerResult, secondsToFirstReply: Double)

    /// `app_opened.entry` の値。
    public enum Entry: String, Sendable, CaseIterable {
        case icon
        case notification
        case widget
        case link
    }

    /// `trip_created.source` の値。
    public enum Source: String, Sendable, CaseIterable {
        case destination
        case paste
        case sampleCopy = "sample_copy"
    }

    /// `consult_answer_finished.result` の値。
    public enum AnswerResult: String, Sendable, CaseIterable {
        case completed
        case failed
        case interrupted
    }

    /// `block_seen.render_id` の値。サーバーが面ごとに作った不透明な値
    ///
    /// 値の全体が `[A-Za-z0-9_-]{8,40}` に合い、64 字までのものだけを作れる。
    public struct RenderId: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形を崩して送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[A-Za-z0-9_-]{8,40}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }

    /// `block_seen.block_key` の値。意味で決めたブロックのキー
    ///
    /// 値の全体が `[a-z]+:[A-Za-z0-9_-]{1,56}` に合い、64 字までのものだけを作れる。
    public struct BlockKey: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形を崩して送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[a-z]+:[A-Za-z0-9_-]{1,56}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }


    public var name: String {
        switch self {
        case .appOpened(_, _): return "app_opened"
        case .tripCreated(_, _): return "trip_created"
        case .blockSeen(_, _, _): return "block_seen"
        case .consultAnswerFinished(_, _): return "consult_answer_finished"
        }
    }

    public var kind: EventKind {
        switch self {
        case .appOpened(_, _): return .screen
        case .tripCreated(_, _): return .outcome
        case .blockSeen(_, _, _): return .impression
        case .consultAnswerFinished(_, _): return .outcome
        }
    }

    public var dedup: DedupScope {
        switch self {
        case .appOpened(_, _): return .session
        case .tripCreated(_, _): return .always
        case .blockSeen(_, _, _): return .always
        case .consultAnswerFinished(_, _): return .always
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .appOpened(firstLaunch, entry): return ["first_launch": .flag(firstLaunch), "entry": .text(entry.rawValue)]
        case let .tripCreated(source, nth): return ["source": .text(source.rawValue), "nth": .bucket(nth, edges: [1, 2, 3])]
        case let .blockSeen(renderId, blockKey, position): return ["render_id": .text(renderId.rawValue), "block_key": .text(blockKey.rawValue), "position": .bucket(position, edges: [1, 2, 3, 5, 10])]
        case let .consultAnswerFinished(result, secondsToFirstReply): return ["result": .text(result.rawValue), "seconds_to_first_reply": .number(secondsToFirstReply)]
        }
    }
}

/// このアプリが置ける属性の全部。
public enum TripUserProperty: AnalyticsUserProperty {

    /// 購読の状態
    case plan(Plan)

    /// 端末にある旅行の数の帯
    case trips(Int)

    /// `plan` の値。
    public enum Plan: String, Sendable, CaseIterable {
        case free
        case trial
        case yearly
        case monthly
    }

    public var name: String {
        switch self {
        case .plan: return "plan"
        case .trips: return "trips"
        }
    }

    public var value: String {
        switch self {
        case let .plan(value): return value.rawValue
        case let .trips(value): return AnalyticsValue.bucket(value, edges: [1, 2, 5]).description
        }
    }
}

// MARK: - 型付きの入口
//
// ポートは `any AnalyticsEvent` を受け取るので、これが無いと発火点で先頭ドットが使えない。

public extension AnalyticsClient {

    func track(_ event: TripEvent) {
        track(event as any AnalyticsEvent)
    }

    func setUserProperty(_ property: TripUserProperty) {
        setUserProperty(property as any AnalyticsUserProperty)
    }
}
