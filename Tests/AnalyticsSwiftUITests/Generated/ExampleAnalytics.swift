// このファイルは analytics-gen.py が書き出しています。手で編集しないでください。
//
// 正典は analytics.yaml。**先にそちらを直してから生成する。**

import AnalyticsCore
import AnalyticsSwiftUI
import SwiftUI

/// このアプリが送れる出来事の全部。
///
/// 増やすときは analytics.yaml を直してから生成し直す。
public enum ExampleEvent: AnalyticsEvent {

    /// 初回体験の 1 枚目に着いた
    ///
    /// 撃つ場所: OnboardingFlowView（同意画面からは撃たない）
    case tutorialBegin

    /// 初回体験を終えてホームに着いた
    case tutorialComplete(items: Int)

    /// 課金の案内が実際に見えた
    ///
    /// 撃つ場所: PaywallView が 50% 以上 1 秒
    case paywallShown(source: Source)

    /// その端末で最初の記録
    case stockFirstRecord(day: Int)

    /// `paywall_shown.source` の値。どの露出点から開いたか
    public enum Source: String, Sendable, CaseIterable {
        case teaser
        case soloCard = "solo_card"
        case gate402 = "gate_402"
    }


    public var name: String {
        switch self {
        case .tutorialBegin: return "tutorial_begin"
        case .tutorialComplete(_): return "tutorial_complete"
        case .paywallShown(_): return "paywall_shown"
        case .stockFirstRecord(_): return "stock_first_record"
        }
    }

    public var kind: EventKind {
        switch self {
        case .tutorialBegin: return .screen
        case .tutorialComplete(_): return .outcome
        case .paywallShown(_): return .impression
        case .stockFirstRecord(_): return .outcome
        }
    }

    public var dedup: DedupScope {
        switch self {
        case .tutorialBegin: return .episode
        case .tutorialComplete(_): return .always
        case .paywallShown(_): return .episode
        case .stockFirstRecord(_): return .install
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case .tutorialBegin: return [:]
        case let .tutorialComplete(items): return ["items": .count(items)]
        case let .paywallShown(source): return ["source": .text(source.rawValue)]
        case let .stockFirstRecord(day): return ["day": .count(day)]
        }
    }
}

/// このアプリが置ける属性の全部。
public enum ExampleUserProperty: AnalyticsUserProperty {

    /// 課金の状態
    case plan(Plan)

    /// 登録件数の帯（生の件数は個人を指しうるので帯にする）
    case itemsBucket(Int)

    /// `plan` の値。
    public enum Plan: String, Sendable, CaseIterable {
        case free
        case paid
    }

    public var name: String {
        switch self {
        case .plan: return "plan"
        case .itemsBucket: return "items_bucket"
        }
    }

    public var value: String {
        switch self {
        case let .plan(value): return value.rawValue
        case let .itemsBucket(value): return AnalyticsValue.bucket(value, edges: [1, 6, 16]).description
        }
    }
}

// MARK: - 型付きの入口
//
// ポートは `any AnalyticsEvent` を受け取るので、これが無いと発火点で先頭ドットが使えない。

public extension AnalyticsClient {

    func track(_ event: ExampleEvent) {
        track(event as any AnalyticsEvent)
    }

    func setUserProperty(_ property: ExampleUserProperty) {
        setUserProperty(property as any AnalyticsUserProperty)
    }
}

public extension View {

    func trackScreen(_ event: ExampleEvent) -> some View {
        trackScreen(event as any AnalyticsEvent)
    }

    @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    func trackImpression(_ event: ExampleEvent) -> some View {
        trackImpression(event as any AnalyticsEvent)
    }
}
