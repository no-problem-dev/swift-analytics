[English](./README_EN.md) | 日本語

# swift-analytics

プロダクト分析（人の行動の計測）のための語彙と、SwiftUI で**正しく数える**ための道具。

`swift-log` / `swift-metrics` のような診断ログではありません。「何人が、どの画面で、
何をしたか」を、あとから分析できる形で残すためのものです。

- **外部依存ゼロ。** 送信先（Firebase / PostHog / 自前のサーバー）はこのパッケージに入っていません
- **数え方をカタログが持つ。** 「1 インストールに 1 回」「見えて 1 秒で 1 回」を発火点に書かせません
- **YAML のカタログから Swift を生成。** 文字列でイベントを送る口はありません

## なぜ作ったか

計測の事故は「出ない」より「**出すぎる**」ほうが多く、そしてどちらもテストでもレビューでも
ダッシュボードでも落ちません。

あるアプリで、初回体験の開始イベントが同意画面と本編の両方から撃たれ、1 インストールにつき
2 回出ていました。完了率は実際の半分に見えていましたが、**型もテストも通り、
ダッシュボードにも「それらしい数字」が並んでいました**。

原因は発火点を 2 箇所に書いたことではありません。**「1 インストールに 1 回」という決めが
どこにも書かれていなかった**ので、2 箇所に書いたことを誰も間違いだと言えなかったことです。

だから数え方を語彙に入れました。

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
**同居させないのは、SwiftPM が依存をパッケージ単位で解決するから** ——
語彙しか使わない消費者にまで vendor の SDK が降ってきてしまいます。

## 使う

### 1. カタログを書く

```yaml
# analytics.yaml
version: 1
dialect: ga4
swift:
  event_type: AppEvent
  property_type: AppUserProperty

events:
  - name: paywall_shown
    kind: impression        # screen | impression | interaction | outcome
    dedup: episode          # episode | session | install | always
    description: 課金の案内が実際に見えた
    parameters:
      source:
        type: enum
        values: [teaser, solo_card, gate_402]
```

仕様は [Schema/SCHEMA.md](./Schema/SCHEMA.md)。

### 2. 生成する

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
```

**生成物はコミットします。** 計測の変更は「何を測ることにしたか」の変更であり、
**差分が唯一のレビュー材料**だからです。ビルド時に生成すると、その差分を誰も見られなくなります。

Python 3 だけで動きます（追加のインストールはありません）。

### 3. 配線する

```swift
import AnalyticsCore
import AnalyticsSwiftUI

let analytics = DedupingAnalytics(
    MultiplexAnalytics([ConsoleAnalytics(), FirebaseAnalyticsClient()])
)

ContentView().analytics(analytics)
```

### 4. 撃つ

```swift
PaywallView()
    .trackScreen(.paywallShown(source: .settings))   // 50% が 1 秒見えたら 1 回

Button("招待を送る") {
    analytics.track(.inviteShareOpened)
}
```

**「もう撃ったか」は書きません。** カタログの `dedup` を `DedupingAnalytics` と
`ImpressionTracker` が実施します。

### 5. CI で守る

```sh
Scripts/analytics-gen.py check --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
Scripts/analytics-gen.py audit --schema analytics.yaml --sources Sources/
```

`audit` が落とすもの:

- カタログにあるのに撃たれていない出来事・値・属性（宣言だけ残ると、ダッシュボードの 0 が「使われていない」と読める）
- **同じ発火が 2 箇所以上にある**（grep では見えない）
- カタログを迂回した文字列直書き

## 「見えた」の定義

```
面積の 50% 以上が、連続して 1.0 秒以上見えていたら 1 回
```

広告計測で決着している基準（MRC）に合わせています。業界標準だからではなく、
**時間を入れないと定義が閉じないから**です。面積だけでは「一瞬映った」を排除できず、
`onAppear` の穴がそのまま残ります。

判定は `ImpressionTracker` が持ち、**時計を持ちません**。「何秒待て」を返すだけなので、
シミュレータも実時間の待ちもなしに数え方を固定できます。

```swift
var tracker = ImpressionTracker()
#expect(tracker.visibility(1.0) == .startDwell(1.0))
#expect(tracker.visibility(0.0) == .cancelDwell)
#expect(tracker.dwellCompleted() == false)   // 0.9 秒で消えたら数えない
```

### 繋ぎもテストできます

**事故が起きるのは定義ではなく繋ぎのほう**です。`onAppear` を 2 箇所に書いた、
`onDisappear` で待ちを止め忘れた、背面でも走り続けた —— どれも `ImpressionTracker` では落ちません。

だから ViewModifier は `ImpressionSession` へ流すだけにしてあり、判断も待ちもそちらにあります。
待ちは注入できるので、**実時間もシミュレータも要りません**。

```swift
let session = ImpressionSession(event: event, client: recorder, sleep: { _ in })

session.appeared()
await session.settled()
session.appeared()          // SwiftUI の再入
await session.settled()
#expect(recorder.count(of: "paywall_shown") == 1)   // 増えない
```

固定してあるのは 10 件 —— 二重の onAppear・途中で閉じた・戻ってきた・背面・
スクロールで通り過ぎた・同じ露出で見え隠れした、など。

## 事実は送りません

「買った」「世帯ができた」「通知を送った」のような**ドメインの事実は、クライアントから
送りません**。事実はサーバーに永続化されていて、それが正典だからです。

同じことをイベントでも送ると必ず食い違い、しかもどちらが正しいかを判定する手段が
なくなります（オフラインで記録して後から同期された分は、発生時刻と送信時刻がずれます）。
数えるときはサーバーのデータを SQL で引きます。

この規律のおかげで、**ユースケース層に計測を挿す必要が消えます** ——
計測がアーキテクチャに寄生しません。

## 端末で確かめる

送信先のデバッグ画面は反映に間があり、`os.Logger` は Mac に繋がないと読めません。
**通知から戻ってきたときの計測は、Xcode を繋いだ状態では再現しにくい**ので、
端末だけで読める口を用意しています。

```swift
let log = AnalyticsLog()
let analytics = DedupingAnalytics(MultiplexAnalytics([
    ConsoleAnalytics(), LoggingAnalytics(log: log), firebase
]))

NavigationLink("計測ログ") { AnalyticsLogViewer(log: log) }
```

見せているのは 3 つです。

- **何が出たか**（名前と引数）
- **どう数えるはずのものか**（種別と数え方）—— 期待とずれた瞬間に目で分かる
- **何回出たか** —— 2 回以上出ているものに `×2` が付く。計測の事故はたいてい「出すぎ」

`LoggingAnalytics` は **`DedupingAnalytics` の内側**に置きます。外に置くと間引かれたものまで
並んで「2 回出ている」と読めてしまうので、実際に送られたものだけを控えます。

## ライセンス

MIT
