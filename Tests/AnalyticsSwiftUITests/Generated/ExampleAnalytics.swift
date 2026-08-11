// This file is written out by analytics-gen.py. Do not edit it by hand.
//
// analytics.yaml is the authoritative copy. **Change that first, then generate.**

import AnalyticsCore
import AnalyticsSwiftUI
import SwiftUI

/// Everything this app is able to send.
///
/// To add one, change analytics.yaml and generate again.
public enum ExampleEvent: AnalyticsEvent {

    /// Arrived at the first page of the first-run experience
    ///
    /// Fired from: OnboardingFlowView (never from the consent screen)
    case tutorialBegin

    /// Finished the first-run experience and arrived at the home screen
    case tutorialComplete(items: Int)

    /// The subscription offer actually became visible
    ///
    /// Fired from: PaywallView, at 50% or more for one second
    case paywallShown(source: Source)

    /// The first record made on this device
    case stockFirstRecord(day: Int)

    /// Values of `paywall_shown.source`: which exposure point it was opened from
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
        case .tutorialBegin: return .always
        case .tutorialComplete(_): return .always
        case .paywallShown(_): return .always
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

/// Every attribute this app is able to set.
public enum ExampleUserProperty: AnalyticsUserProperty {

    /// Subscription state
    case plan(Plan)

    /// Band for the number of records held (raw counts can point at one person, so they are
    /// banded)
    case itemsBucket(Int)

    /// Values of `plan`.
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

// MARK: - Typed entry points
//
// The port takes `any AnalyticsEvent`, so without these a firing point cannot use leading-dot
// syntax.

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
