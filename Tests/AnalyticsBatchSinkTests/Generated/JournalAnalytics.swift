// このファイルは analytics-gen.py が書き出しています。手で編集しないでください。
//
// 元は analytics.yaml。**先にそちらを直してから生成する。**

import AnalyticsCore

/// このアプリが送れる出来事の全部。
///
/// 増やすときは analytics.yaml を直してから生成し直す。
public enum JournalEvent: AnalyticsEvent {

    /// 画面が表示された
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    ///
    /// 撃つ場所: trackScreen
    case screenViewed(screen: ScreenName)

    /// 計測すると決めたボタンを押した
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    ///
    /// 撃つ場所: ボタンを押したとき
    case tapped(target: TapTarget, screen: ScreenName)

    /// オンボーディングのステップに来た
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    ///
    /// 撃つ場所: 各ステップの画面
    case onboardingStep(step: OnboardingStep, index: Int)

    /// オンボーディングを最後まで通った
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    ///
    /// 撃つ場所: 最後のステップを抜けたとき
    case onboardingCompleted

    /// サインインが成立した
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case signedIn(provider: SignInProvider, source: SignInSource)

    /// 実験の群に入った
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case experimentAssigned(experiment: Experiment, arm: Arm)

    /// ペイウォールが表示された
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallShown(source: PaywallSource, pwId: PwId, nth: Int, variant: Variant)

    /// 価格を読み終えた
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallLoaded(source: PaywallSource, pwId: PwId, result: PaywallLoadResult, loadS: Double)

    /// ペイウォールの区切りが初めて画面に入った（1回の表示につき区切りごとに1回）
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallScrolled(source: PaywallSource, pwId: PwId, section: PaywallSection)

    /// プランを切り替えた
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallPlanSelected(source: PaywallSource, pwId: PwId, to: PlanPeriod)

    /// 購入ボタンを押した
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallPurchaseTapped(source: PaywallSource, pwId: PwId, product: PlanPeriod, openS: Int)

    /// 購入の結果が返った
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallPurchaseResult(source: PaywallSource, pwId: PwId, product: PlanPeriod, result: PurchaseResult, sheetS: Int)

    /// ペイウォールを出したままアプリが裏に回った
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallBackgrounded(source: PaywallSource, pwId: PwId, openS: Int)

    /// ペイウォールを閉じた
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case paywallClosed(source: PaywallSource, pwId: PwId, result: PaywallCloseResult, via: PaywallCloseVia, product: PlanPeriod? = nil, openS: Int)

    /// ペイウォールの上で購入が成立した（ペイウォールごとの転換に使う。売上と継続の数字は RevenueCat から読む）
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case purchaseCompleted(source: PaywallSource, pwId: PwId, product: PlanPeriod)

    /// 復元の結果が返った
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case restoreCompleted(source: RestoreSource, result: RestoreResult)

    /// OS の評価の画面を呼んだ（出たかはアプリから分からない。呼んだら1回と数える）
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    ///
    /// 撃つ場所: swift-review が頼むと決めたとき
    case reviewRequested(moment: ReviewMomentName)

    /// 新しいバージョンのお知らせを出した
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case whatsNewShown(release: Release)

    /// お知らせを閉じた
    ///
    /// 共通カタログ（common）の出来事。名前と共通の引数はアプリで変えない。
    case whatsNewClosed(release: Release, page: Int, pages: Int, via: WhatsNewCloseVia)

    /// 日記を保存した
    case entrySaved(screen: ScreenName, words: Int)

    /// `screen_viewed.screen` の値。
    public enum ScreenName: String, Sendable, CaseIterable {
        case onboarding
        case paywall
        case settings
        case whatsNew = "whats_new"
        case home
        case entry
    }

    /// `tapped.target` の値。
    public enum TapTarget: String, Sendable, CaseIterable {
        case close
        case `continue`
        case purchase
        case restore
        case review
        case share
    }

    /// `onboarding_step.step` の値。
    public enum OnboardingStep: String, Sendable, CaseIterable {
        case paywall
    }

    /// `signed_in.provider` の値。other = 上のどれでもないサインインの方法
    public enum SignInProvider: String, Sendable, CaseIterable {
        case apple
        case google
        case anonymous
        case email
        case other
    }

    /// `signed_in.source` の値。
    public enum SignInSource: String, Sendable, CaseIterable {
        case onboarding
        case settings
        case gate
    }

    /// `paywall_shown.source` の値。どこから開いたか
    public enum PaywallSource: String, Sendable, CaseIterable {
        case onboarding
        case settings
        case limit
        case entryLimit = "entry_limit"
    }

    /// `paywall_shown.variant` の値。ペイウォールの見た目の版
    public enum Variant: String, Sendable, CaseIterable {
        case cards
        case plain
    }

    /// `paywall_loaded.result` の値。
    public enum PaywallLoadResult: String, Sendable, CaseIterable {
        case ok
        case unavailable
    }

    /// `paywall_scrolled.section` の値。
    public enum PaywallSection: String, Sendable, CaseIterable {
        case benefits
        case plans
        case comparison
    }

    /// `paywall_plan_selected.to` の値。
    public enum PlanPeriod: String, Sendable, CaseIterable {
        case yearly
        case monthly
        case weekly
        case lifetime
    }

    /// `paywall_purchase_result.result` の値。
    public enum PurchaseResult: String, Sendable, CaseIterable {
        case purchased
        case cancelled
        case pending
        case failed
    }

    /// `paywall_closed.result` の値。
    public enum PaywallCloseResult: String, Sendable, CaseIterable {
        case purchased
        case restored
        case dismissed
    }

    /// `paywall_closed.via` の値。
    public enum PaywallCloseVia: String, Sendable, CaseIterable {
        case closeButton = "close_button"
        case later
        case continueFree = "continue_free"
        case auto
        case swipeDown = "swipe_down"
    }

    /// `restore_completed.source` の値。
    public enum RestoreSource: String, Sendable, CaseIterable {
        case paywall
        case settings
    }

    /// `restore_completed.result` の値。
    public enum RestoreResult: String, Sendable, CaseIterable {
        case restored
        case nothingToRestore = "nothing_to_restore"
        case failed
    }

    /// `review_requested.moment` の値。
    public enum ReviewMomentName: String, Sendable, CaseIterable {
        case afterWhatsNew = "after_whats_new"
    }

    /// `whats_new_closed.via` の値。
    public enum WhatsNewCloseVia: String, Sendable, CaseIterable {
        case closeButton = "close_button"
        case finished
        case swipeDown = "swipe_down"
    }

    /// `experiment_assigned.experiment` の値。
    ///
    /// 値の全体が `[a-z0-9_]{1,40}` に合い、64 字までのものだけを作れる。
    public struct Experiment: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形の違う値を送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[a-z0-9_]{1,40}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }

    /// `experiment_assigned.arm` の値。
    ///
    /// 値の全体が `[a-z0-9_]{1,40}` に合い、64 字までのものだけを作れる。
    public struct Arm: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形の違う値を送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[a-z0-9_]{1,40}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }

    /// `paywall_shown.pw_id` の値。1回の表示ごとの短い ID。閉じるまで同じ
    ///
    /// 値の全体が `[a-f0-9]{8}` に合い、64 字までのものだけを作れる。
    public struct PwId: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形の違う値を送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[a-f0-9]{8}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }

    /// `whats_new_shown.release` の値。お知らせのバージョン
    ///
    /// 値の全体が `[0-9]{1,3}(\.[0-9]{1,3}){1,2}` に合い、64 字までのものだけを作れる。
    public struct Release: Sendable, Hashable, CustomStringConvertible {

        public let rawValue: String

        /// 形に合わなければ nil。**送らずに済ませる**（形の違う値を送るより、送らない方が数を壊さない）。
        public init?(_ rawValue: String) {
            guard rawValue.count <= 64,
                  let pattern = try? Regex(#"[0-9]{1,3}(\.[0-9]{1,3}){1,2}"#),
                  (try? pattern.wholeMatch(in: rawValue)) != nil
            else { return nil }
            self.rawValue = rawValue
        }

        public var description: String { rawValue }
    }


    public var name: String {
        switch self {
        case .screenViewed(_): return "screen_viewed"
        case .tapped(_, _): return "tapped"
        case .onboardingStep(_, _): return "onboarding_step"
        case .onboardingCompleted: return "onboarding_completed"
        case .signedIn(_, _): return "signed_in"
        case .experimentAssigned(_, _): return "experiment_assigned"
        case .paywallShown(_, _, _, _): return "paywall_shown"
        case .paywallLoaded(_, _, _, _): return "paywall_loaded"
        case .paywallScrolled(_, _, _): return "paywall_scrolled"
        case .paywallPlanSelected(_, _, _): return "paywall_plan_selected"
        case .paywallPurchaseTapped(_, _, _, _): return "paywall_purchase_tapped"
        case .paywallPurchaseResult(_, _, _, _, _): return "paywall_purchase_result"
        case .paywallBackgrounded(_, _, _): return "paywall_backgrounded"
        case .paywallClosed(_, _, _, _, _, _): return "paywall_closed"
        case .purchaseCompleted(_, _, _): return "purchase_completed"
        case .restoreCompleted(_, _): return "restore_completed"
        case .reviewRequested(_): return "review_requested"
        case .whatsNewShown(_): return "whats_new_shown"
        case .whatsNewClosed(_, _, _, _): return "whats_new_closed"
        case .entrySaved(_, _): return "entry_saved"
        }
    }

    public var kind: EventKind {
        switch self {
        case .screenViewed(_): return .screen
        case .tapped(_, _): return .interaction
        case .onboardingStep(_, _): return .screen
        case .onboardingCompleted: return .outcome
        case .signedIn(_, _): return .outcome
        case .experimentAssigned(_, _): return .outcome
        case .paywallShown(_, _, _, _): return .impression
        case .paywallLoaded(_, _, _, _): return .outcome
        case .paywallScrolled(_, _, _): return .impression
        case .paywallPlanSelected(_, _, _): return .interaction
        case .paywallPurchaseTapped(_, _, _, _): return .interaction
        case .paywallPurchaseResult(_, _, _, _, _): return .outcome
        case .paywallBackgrounded(_, _, _): return .outcome
        case .paywallClosed(_, _, _, _, _, _): return .outcome
        case .purchaseCompleted(_, _, _): return .outcome
        case .restoreCompleted(_, _): return .outcome
        case .reviewRequested(_): return .outcome
        case .whatsNewShown(_): return .impression
        case .whatsNewClosed(_, _, _, _): return .outcome
        case .entrySaved(_, _): return .outcome
        }
    }

    public var dedup: DedupScope {
        switch self {
        case .screenViewed(_): return .always
        case .tapped(_, _): return .always
        case .onboardingStep(_, _): return .always
        case .onboardingCompleted: return .install
        case .signedIn(_, _): return .always
        case .experimentAssigned(_, _): return .install
        case .paywallShown(_, _, _, _): return .always
        case .paywallLoaded(_, _, _, _): return .always
        case .paywallScrolled(_, _, _): return .always
        case .paywallPlanSelected(_, _, _): return .always
        case .paywallPurchaseTapped(_, _, _, _): return .always
        case .paywallPurchaseResult(_, _, _, _, _): return .always
        case .paywallBackgrounded(_, _, _): return .always
        case .paywallClosed(_, _, _, _, _, _): return .always
        case .purchaseCompleted(_, _, _): return .always
        case .restoreCompleted(_, _): return .always
        case .reviewRequested(_): return .always
        case .whatsNewShown(_): return .always
        case .whatsNewClosed(_, _, _, _): return .always
        case .entrySaved(_, _): return .always
        }
    }

    public var parameters: [String: AnalyticsValue] {
        switch self {
        case let .screenViewed(screen): return ["screen": .text(screen.rawValue)]
        case let .tapped(target, screen): return ["target": .text(target.rawValue), "screen": .text(screen.rawValue)]
        case let .onboardingStep(step, index): return ["step": .text(step.rawValue), "index": .count(index)]
        case .onboardingCompleted: return [:]
        case let .signedIn(provider, source): return ["provider": .text(provider.rawValue), "source": .text(source.rawValue)]
        case let .experimentAssigned(experiment, arm): return ["experiment": .text(experiment.rawValue), "arm": .text(arm.rawValue)]
        case let .paywallShown(source, pwId, nth, variant): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "nth": .bucket(nth, edges: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]), "variant": .text(variant.rawValue)]
        case let .paywallLoaded(source, pwId, result, loadS): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "result": .text(result.rawValue), "load_s": .number(loadS)]
        case let .paywallScrolled(source, pwId, section): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "section": .text(section.rawValue)]
        case let .paywallPlanSelected(source, pwId, to): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "to": .text(to.rawValue)]
        case let .paywallPurchaseTapped(source, pwId, product, openS): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "product": .text(product.rawValue), "open_s": .count(openS)]
        case let .paywallPurchaseResult(source, pwId, product, result, sheetS): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "product": .text(product.rawValue), "result": .text(result.rawValue), "sheet_s": .count(sheetS)]
        case let .paywallBackgrounded(source, pwId, openS): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "open_s": .count(openS)]
        case let .paywallClosed(source, pwId, result, via, product, openS):
            var parameters: [String: AnalyticsValue] = ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "result": .text(result.rawValue), "via": .text(via.rawValue), "open_s": .count(openS)]
            if let product { parameters["product"] = .text(product.rawValue) }
            return parameters
        case let .purchaseCompleted(source, pwId, product): return ["source": .text(source.rawValue), "pw_id": .text(pwId.rawValue), "product": .text(product.rawValue)]
        case let .restoreCompleted(source, result): return ["source": .text(source.rawValue), "result": .text(result.rawValue)]
        case let .reviewRequested(moment): return ["moment": .text(moment.rawValue)]
        case let .whatsNewShown(release): return ["release": .text(release.rawValue)]
        case let .whatsNewClosed(release, page, pages, via): return ["release": .text(release.rawValue), "page": .count(page), "pages": .count(pages), "via": .text(via.rawValue)]
        case let .entrySaved(screen, words): return ["screen": .text(screen.rawValue), "words": .bucket(words, edges: [1, 50, 200])]
        }
    }
}

/// このアプリが置ける属性の全部。
public enum JournalUserProperty: AnalyticsUserProperty {

    public var name: String {
        switch self {
        }
    }

    public var value: String {
        switch self {
        }
    }
}

// MARK: - 型付きの track と setUserProperty
//
// ポートは `any AnalyticsEvent` を受け取るので、これが無いと発火点で先頭ドットが使えない。

public extension AnalyticsClient {

    func track(_ event: JournalEvent) {
        track(event as any AnalyticsEvent)
    }
}
