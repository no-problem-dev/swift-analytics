[English](./README.md) | 日本語

# swift-analytics

プロダクト分析（人の行動の計測）のための語彙と、SwiftUI で正しく数えるための道具。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20watchOS%2010%20%7C%20visionOS%201-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

`swift-log` / `swift-metrics` のような診断ログではありません。「何人が、どの画面で、何をしたか」を、
あとから分析できる形で残すためのものです。

計測の事故は「出ない」より**出すぎる**ほうが多く、そしてどちらもテストでもレビューでも
ダッシュボードでも落ちません。原因は発火点を 2 箇所に書いたことではなく、
**数え方がどこにも書かれていなかった**ので、2 箇所に書いたことを誰も間違いだと言えなかったことです。
だから数え方を語彙に入れました。

## 特徴

- **数え方をカタログが持つ。**「1 インストールに 1 回」「見えて 1 秒で 1 回」を発火点に覚えさせません
- **カタログから Swift を生成する。** 文字列でイベントを送る口が無いので、名前の打ち間違いも、
  宣言していない引数の混入も起きません
- **重複の間引きは実施であって記憶ではない。** 宣言した範囲を `DedupingAnalytics` が実施し、
  発火点は「もう撃ったか」を一切書きません
- **「見えた」の定義が閉じている。** 面積の 50% 以上が連続して 1.0 秒。判定器は時計を持たないので、
  シミュレータも実時間の待ちもなしにユニットテストで固定できます
- **grep では書けない CI 監査。** 宣言だけで撃たれていない出来事・同じ発火が 2 箇所にあること・
  カタログを迂回した文字列直書きを、すべてビルドで落とします
- **外部依存ゼロ。** SwiftPM は依存をパッケージ単位で解決するので、送信先（Firebase / PostHog /
  自前のサーバー）は別パッケージに置いています
- **端末で読めるログ画面。** 実際に送られたものを、種別・数え方つきで、2 回出ているものには `×2` を付けて表示します

## クイックスタート

出来事と、その数え方を宣言します。

```yaml
# analytics.yaml
version: 1
dialect: ga4
swift:
  event_type: AppEvent

events:
  - name: paywall_shown
    kind: impression        # screen | impression | interaction | outcome
    dedup: episode          # episode | session | install | always
    description: 課金の案内が実際に見えた
```

Swift を生成し、**生成物はコミットします**。計測の変更は「何を測ることにしたか」の変更であり、
差分が唯一のレビュー材料だからです。

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
```

発火点はこれだけです。

```swift
import AnalyticsSwiftUI

PaywallView().trackScreen(.paywallShown)
```

## ドキュメント

[**API リファレンスとガイド**](https://no-problem-dev.github.io/swift-analytics/documentation/) —
[Getting Started](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/gettingstarted/)、
[Counting Rules](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/countingrules/)、
[What Not to Send](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/whatnottosend/) を含みます。

カタログの書式は [Schema/SCHEMA.md](./Schema/SCHEMA.md) が仕様です。

## 導入

```swift
.package(url: "https://github.com/no-problem-dev/swift-analytics.git", from: "0.1.0")
```

| プロダクト | 中身 | 依存 |
|---|---|---|
| `AnalyticsCore` | 語彙・ポート・数え方 | なし |
| `AnalyticsSwiftUI` | 画面から撃つ層・端末で読むログ | SwiftUI |
| `AnalyticsTesting` | テストの土台 | なし |

送信先のアダプタは別パッケージです（[swift-analytics-firebase](https://github.com/no-problem-dev/swift-analytics-firebase)）。
同居させると、語彙しか使わない消費者にまで vendor の SDK が降ってきます。

生成器は Python 3 だけで動きます（追加のインストールはありません）。

## 動作環境

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+ / watchOS 10.0+ / visionOS 1.0+
- Swift 6.2+
- Python 3（カタログ生成器のみ）

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
