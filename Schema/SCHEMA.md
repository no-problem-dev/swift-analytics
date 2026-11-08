# analytics.yaml — 計測カタログの正典

アプリごとに 1 つ持つ。ここに書かれていない出来事は送れない。

**先にこのファイルを直してから実装する。** 逆順にすると、実装を読まないと何を測っているか
分からなくなり、エンジニア以外は計測の話に参加できなくなる。

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json] [--ts catalog.ts]
Scripts/analytics-gen.py check    --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json] [--ts catalog.ts]
Scripts/analytics-gen.py audit    --schema analytics.yaml --sources Sources/
```

- `generate` … Swift を書き出す。`--json` を付けると、受け口（サーバー）が照らし合わせに使う JSON も書き出す
  （下の「--json の形」）。`--ts` は受け口（Worker・studio）が import する TypeScript（下の「--ts の形」）。
  `--out`・`--json`・`--ts` はどれか 1 つだけでもよい。**人の手元で走らせ、生成物をコミットする**
- `check` … 生成物（渡した方の全部）がスキーマとずれていたら落ちる。CI に置く
- `audit` … カタログにあるのに撃たれていない／同じ発火が 2 箇所にある、を落とす。CI に置く
- 3 つとも `--common <path>` で `include: common` の読み先を替えられる（省くとこのパッケージの
  `Schema/common/common.yaml`。SwiftPM の checkout の中の生成器を使えば、そのバージョンの共通カタログが読まれる）

---

## 全体

```yaml
version: 1            # カタログの版。受け口と食い違いうる変更をしたら上げる（--json の catalogVersion）
dialect: ga4          # 送信先の方言（ga4 | first_party | envelope）。名前と値の制約を生成時に検査する
include: common       # 任意。共通カタログを取り込む（dialect: envelope のときだけ。下の「include と extend」）
swift:
  event_type: StockEvent           # 生成する enum の名前
  property_type: StockUserProperty
  module: StockAnalytics           # 生成物を置くモジュール名（doc コメントに出るだけ）
  swiftui: true                    # trackScreen / trackImpression の型付き口も生成する
  descriptions: true               # 任意。false にすると description と trigger を生成物の doc コメントに写さない
                                   # （アプリの日本語の lint を生成物にも掛けたいときなど）

extend: [...]         # 任意。共通の出来事に enum の値と引数を足す
events: [...]
user_properties: [...]
facts: [...]          # 任意。サーバーから数えるもの。**Swift は生成されない**
```

頭に書ける鍵はこの 9 つ（と `name`）だけ。ほかの鍵は打ち間違いとして落とす。

## events

```yaml
events:
  - name: paywall_shown            # 送信先へ送る名前。snake_case
    case: paywallShown             # 任意。省略時は name から lowerCamelCase を作る
    kind: impression               # screen | impression | interaction | outcome
    dedup: always                  # session | install | always
    description: ふたりプランの案内が実際に見えた
    trigger: PaywallView が 50% 以上 1 秒       # 任意。どこで撃つかの申し送り
    track_reason: ...              # 任意。screen / impression を track() で撃ってよい理由（下の「track_reason」）
    parameters:
      source:
        type: enum
        values: [teaser, solo_card, gate_402]
        description: どの露出点から開いたか
```

### parameters の型

| type | Swift | 用途 |
|---|---|---|
| `enum` | 生成される入れ子の enum | **既定はこれ。**自由文字列を作らせない |
| `count` | `Int` | 個数・日数 |
| `number` | `Double` | 割合・秒 |
| `flag` | `Bool` | 真偽。GA4 では 0/1 に落ちる |
| `bucket` | `Int` を受け取り帯に落とす | 生の件数を送らないための型。`edges: [1, 6, 16]`。帯の名前は `labels:` で決められる（下の「bucket の帯の名前」） |
| `token` | 生成される入れ子の struct（`init?(_:)`） | **サーバーが作った不透明な値**（`render_id`）と、**意味で決めたキー**（`place:ChIJ…`）だけ。出来事の引数にだけ使え、属性には使えない |

`enum` の値は `snake_case` で書く。Swift 側の case 名は自動で lowerCamelCase になり、
raw 値は書いたままが送られる。

### bucket の帯の名前

既定の帯の名前は `AnalyticsValue.bucket(_:edges:)` が作る（`edges: [1, 6, 16]` なら `0`・`1_5`・`6_15`・`16_plus`）。
受け手がもう別の名前を読んでいるときは `labels:` で決める。

```yaml
      streak:
        type: bucket
        edges: [1, 2, 10]
        labels: ["0", "1", "2_9", "10+"]   # 1 つ目は一番下の edge より下。続きは edge ごと（昇順）
```

- `labels` は `edges` より 1 つ多い。`edges` は小さい順に、重ねずに書く
- 名前は英小文字・数字・`_` `+` `.` `-` だけ。同じ名前は 2 回書けない。`+` を含む名前は引用符で書く
- Swift は `AnalyticsValue.bucket(_:edges:labels:)` で送る。`--json` と `--ts` の `values` は `labels` になる
- 引数にも属性にも書ける。共通の引数の `labels` は `extend:` で変えられない

### optional

```yaml
      product:
        type: enum
        type_name: PlanPeriod
        values: [yearly, monthly, weekly, lifetime]
        optional: true               # 値が無いことがある（買わずに閉じた・プランを読めなかった）
```

- どの型にも書ける。生成される Swift の引数は `PlanPeriod? = nil` になり、**nil なら `props` に載らない**
  （空の文字や 0 にして送らない）。省いて呼べるので、値を持たない場面では書かなくてよい
- `--json` では引数に `"optional": true` が付く（無ければ必須）。`--ts` の `EventProps` では `product?:`
- 「分からない」を enum の値（`unknown`）にしない。値が無いことは、引数が無いことで表す
- 共通の引数も、アプリの `extend:` で `optional: true` にできる（その場面で値を持てないアプリのため）。
  共通で任意の引数を必須に戻す書き方は無い

### track_reason

`kind` が `screen` か `impression` の出来事は、`trackScreen` / `trackImpression` で撃つ（下の「検査されること」）。
**見える物（View）が無い場所から送るしかない**とき —— シートを出した後のコールバック、お知らせを出した知らせ ——
だけ、理由を書いて `track()` でも撃てるようにする。

```yaml
extend:
  - name: paywall_shown
    track_reason: 画面ごとのペイウォールはシートを出したコールバックから送る（PaywallSheet.onPresented）
```

- 書けるのは `kind` が `screen` か `impression` の出来事だけ。アプリの出来事は `events:` に、共通の出来事は `extend:` に書く
- 書いても `trackImpression` / `trackScreen` で撃つ所はそのまま通る
- `track()` で撃つ所では、1 回の表示を 1 回と数えるのはアプリの責任になる（`pw_id` のように 1 回の表示ごとの ID で束ねる）

### token

自由な文字列の口ではない。形を正規表現で閉じ、**形に合う値しか作れない型**を生成する。

```yaml
      render_id:
        type: token
        pattern: "[A-Za-z0-9_-]{8,40}"   # 必須。値の**全体**が合うこと（^ と $ は要らない）
        max_length: 40                   # 任意。省略すると方言の値の上限（first_party 64・ga4 100）
```

```swift
guard let renderID = TripEvent.RenderId(surface.renderId) else { return }   // 形に合わなければ送らない
analytics.track(.blockSeen(renderId: renderID, blockKey: key, position: index + 1))
```

- `pattern` は Python の `re` と Swift の `Regex` の両方で読む。両方に共通する書き方（文字クラス・`{m,n}`・`+`・`*`・`?`・`|`）に留める
- 空の文字列に合う `pattern`（`[a-z]*` など）は落とす
- 同じ型名（既定は鍵から作る。`type_name` で変えられる）を複数の出来事で使うときは、`pattern` と `max_length` が同じであること

### 引数の名前に使えない語

`name`・`email`・`place`・`text`・`title`・`address` は、引数の名前の `_` で区切った語のどれにも使えない
（`place_name`・`first_text` は落ち、`placement` は通る）。方言によらない。
**人を指す値や、人が書いた文を引数に載せる入口を名前の段階で塞ぐ**ため。

## include と extend

どのアプリにもある出来事（入口・ペイウォール・評価・お知らせ）は、このパッケージの
[common/common.yaml](common/common.yaml) が持つ。アプリのカタログは `include: common` で取り込み、
**名前と共通の引数を手で写さない**。名前を変えたら、共通カタログの差分と受け口の生成物の差分で分かる。

```yaml
version: 3
dialect: envelope
include: common

extend:
  - name: screen_viewed
    parameters:
      screen:
        values: [home, entry]        # extensible: true の enum に値を足す
  - name: paywall_shown
    parameters:
      variant:                       # 共通の出来事に引数を足す（後ろに付く）
        type: enum
        values: [cards, plain]

events:
  - name: entry_saved                # アプリ固有の出来事
    kind: outcome
    dedup: always
    parameters:
      screen: { type: enum, type_name: ScreenName }   # 共通の enum を型名だけで使う（足した値も入る）
```

例は [example-common.yaml](example-common.yaml)（生成物は `example-common.catalog.json`・`example-common.catalog.ts`・
`Tests/AnalyticsBatchSinkTests/Generated/JournalAnalytics.swift`）。

| 決まり | 破ったら |
|---|---|
| `include` は `dialect: envelope` のカタログでだけ使える。共通の出来事は固定の封筒で送る前提で、ga4 の予約名（`first_open`）にも first_party の列の数にも収まらない | 落ちる |
| 共通の出来事を `events:` に書き直さない。値や引数は `extend:` で足す | 落ちる |
| `extend:` に書けるのは共通カタログにある出来事だけ | 落ちる |
| 共通の引数に書けるのは `values` と `optional: true` だけ（`type`・`type_name`・`edges`・`pattern` などは変えられない） | 落ちる |
| 値を足せるのは `extensible: true` の enum だけ。共通の値をもう一度書くこと、同じ値を 2 回足すことはできない | 落ちる |
| 共通の値・引数を消す書き方は無い | — |

- **値は型（`type_name`）ごとに足す。** `ScreenName` は `screen_viewed` と `tapped` の両方が使うので、
  `screen_viewed` に足した `home` は `tapped.screen` にも入る（同じ型名で値の違う状態を作らない）
- アプリの出来事の enum が、共通の型名を `values` なしで書いたら、その値（足した値を含む）を使う
- 生成される Swift は 1 つの型（`swift.event_type`）に、共通の出来事とアプリの出来事が並ぶ

### extensible

```yaml
      screen:
        type: enum
        type_name: ScreenName
        extensible: true             # 取り込んだアプリが値を足してよい
        values: [onboarding, paywall, settings, whats_new]
```

`enum` にだけ書ける。同じ型名を使う場所はどれも同じ `extensible` にする。共通カタログの enum は、
AnalyticsCore が送る `FirstOpenKind` のほかはどれも `extensible: true`（`PaywallCloseResult` の `continue_free`、
`PlanPeriod` の `quarterly` などをアプリが足せる）。アプリのカタログの enum に書いてもよいが、
`--json` と `--ts` に載るだけで生成器の動きは変わらない。

### sent_by: package

共通カタログの `first_open` と `internal_device` は、AnalyticsCore が自分で送る
（`FirstLaunch.recordLaunch(sendingTo:)`・`AnalyticsInternalDevice.mark(sendingTo:)`）。`sent_by: package` の出来事は
**アプリの Swift の型に出さず**、`--json` と `--ts` にだけ載る。送る口を 1 つにして、2 か所から撃てないようにする。
`audit` もこの出来事を数えない。`sent_by` は共通カタログにだけ書ける。

### audit と共通の出来事

アプリにその場面が無い共通の出来事（お知らせが無いアプリの `whats_new_*` など）は、撃っていなくても落とさず、
`（知らせ）` の行で知らせるだけ。値の確かめも、共通の enum では**アプリが足した値**だけを見る
（`PaywallSource` の `limit` が無いアプリもある）。アプリの出来事・アプリが足した値・アプリの引数は、今までどおり全部を確かめる。

### audit の数え方

- **撃っているか**は、出来事を作る式（`.paywallShown(…)`・`.entrySaved`）がソースのどこかにあるかで見る。
  `track(` の中でなくてよい（`send { .paywallShown(source: $0, …) }`、出来事を作って返す関数、`trackImpression(shown)`）
- **値は型（`type_name`）ごとに数える。** `extend:` で `ScreenName` に足した `home` は、`screen_viewed`・`tapped`・
  `ScreenName` を使うアプリの出来事のどれかで直書きされていれば撃っている
- 値を探すのは、その型を使う出来事を作る式の括弧の中だけ
- **確かめる値（アプリの型なら全部、共通の型ならアプリが足した値）が 1 つも直書きされていない型は見ない。**
  変数で渡している（`source: source`・`role.measured`）ので、静的には確かめられない。
  共通の値（`.onboarding`）の直書きは数えない —— アプリが足した値を全部直書きする理由にならない
- 生成物（頭に「このファイルは analytics-gen.py が書き出しています」のあるファイル）と `//` のコメントは見ない

## user_properties

```yaml
user_properties:
  - name: plan
    case: plan
    type: enum
    values: [free, futari]
    description: 課金の状態
  - name: items_bucket
    type: bucket
    edges: [1, 6, 16]
    description: 登録件数の帯
```

## facts（任意・Swift は生成されない）

サーバーの正典から数えるもの。**クライアントから送らない**ので Swift は出ないが、
「何を測ることにしたか」を 1 か所に集めるためにここへ書く。

**`fact` にするのは、サーバーにしか無い事実だけ。** 世帯を作った・通知を送った、のように、サーバーの記録が正本で、
クライアントから送ると必ず食い違うもの。

**`purchase_completed` は `fact` ではない。** 共通カタログの `purchase_completed` は「この壁で買った」という
**画面の上の結果**で、クライアントから送ってよい。ペイウォールの `source`・`pw_id` ごとの転換を出すのに要り、
サーバーの購入の記録には「どの壁から買ったか」が無い。**売上と継続の正本は RevenueCat** に置き、
数字はそこから読む。`purchase_completed` の数を売上として数えない。

```yaml
facts:
  - name: notified_before_empty
    description: 切れる前に通知が出た品目
    source: d1
    query: queries/notified_before_empty.sql
```

---

## 検査されること

`generate` と `check` が、書き出す前に落とす。

| 検査 | なぜ |
|---|---|
| 名前の重複（`name` + パラメータの組） | 同じ出来事を 2 通りに定義しない |
| Swift の型名の衝突 | 生成物がコンパイルできない形にしない |
| 方言の制約（下の表） | **破った送信は成功に見えて捨てられる** |
| 引数の名前に使えない語（上の節） | 人を指す値・人が書いた文を送る入口を作らない |
| `token` の `pattern` が読めて、空の文字列に合わないか | 形の閉じていない token は自由な文字列と同じ |
| `enum` 値が snake_case か | 送信先で値の集合が割れない |

### 方言

| | `ga4` | `first_party` | `envelope` |
|---|---|---|---|
| 送り先 | Firebase Analytics（`swift-analytics-firebase`） | 1 件を固定の列に書く自前の受け口 | 固定の封筒（[common/ENVELOPE.md](common/ENVELOPE.md)）を受ける自前の受け口。`AnalyticsBatchSink` が送る |
| 名前（出来事・属性） | 40 字まで・英字で始まる英数字と `_`・予約接頭辞（`firebase_` `google_` `ga_`）と予約イベント名を落とす | 40 字まで・`snake_case`。引数の名前も同じ | `first_party` と同じ |
| 引数の数 | 25 個まで | **次元（`enum`・`flag`・`bucket`）4 つ・数（`count`・`number`）1 つ・`token` 2 つ**まで | 上限なし（`props` は 1 段の JSON のマップ） |
| 値（`enum` の値・`token` の長さ） | 100 字まで | 64 字まで | 64 字まで |
| `include: common` | 使えない | 使えない | 使える |

`first_party` の引数の数は、受け口が 1 件を固定の列（名前・種別・次元 4・token 2・数 1）に書くことから来る。
受け口は、次元を**カタログに書いた順に** 1〜4 番目の列へ置く。`envelope` の受け口は `props` を JSON のまま持つので、
列の数の上限が無い。**新しく作るカタログは `envelope` にする。**

`audit` は実装側を見る。

| 検査 | なぜ |
|---|---|
| カタログの全ケース・全値が 1 箇所以上から撃たれているか | 宣言だけ残ると、ダッシュボードの 0 が「使われていない」と読める |
| **同じ発火（引数まで込みで同じもの）が 2 箇所以上に無いか** | 1 回の閲覧で複数回撃つ事故は、テストでもレビューでも落ちない |
| **`kind` に合った撃ち方をしているか**（`screen`→`trackScreen` / `impression`→`trackImpression` / `interaction`・`outcome`→`track`。`track_reason` のある出来事は `track` も可） | 表示を 1 露出 1 回に留めるのはこの 2 つだけ。`track()` で撃つと、その規則がどこにも掛からない |
| 属性が 1 箇所以上から設定されているか | 宣言だけの属性はセグメントが空になる |
| 文字列直書きの送信が無いか | カタログを迂回されると検査が意味を失う |

---

## --json の形

受け口（サーバー）が、届いた束をカタログと照らし合わせるための JSON。`generate --json` が書き出し、
`check --json` がずれを落とす。例は [example-first-party.catalog.json](example-first-party.catalog.json)
（[example-first-party.yaml](example-first-party.yaml) から生成）。

```json
{
  "format": 1,
  "generator": "swift-analytics/Scripts/analytics-gen.py",
  "catalogVersion": 1,
  "dialect": "first_party",
  "limits": { "value": 64, "name": 40, "dimensions": 4, "numbers": 1, "tokens": 2 },
  "events": [
    {
      "name": "block_seen", "kind": "impression", "dedup": "always",
      "parameters": [
        { "key": "render_id", "type": "token", "pattern": "[A-Za-z0-9_-]{8,40}", "maxLength": 64 },
        { "key": "position", "type": "bucket", "edges": [1, 2, 3, 5, 10],
          "values": ["0", "1_1", "2_2", "3_4", "5_9", "10_plus"] }
      ]
    }
  ],
  "userProperties": [
    { "name": "plan", "type": "enum", "values": ["free", "trial", "yearly", "monthly"] }
  ],
  "facts": [
    { "name": "trips_created_daily", "source": "d1", "query": "queries/trips_created_daily.sql" }
  ]
}
```

| 鍵 | 中身 |
|---|---|
| `format` | この JSON の形の版。形を変えたら上げる（今は 1） |
| `catalogVersion` | YAML の `version`。アプリは束の頭でこの値を送り、受け口は自分の知る版と比べられる |
| `dialect` | YAML の `dialect` |
| `limits` | 方言の上限。`first_party` は `value`・`name`・`dimensions`・`numbers`・`tokens`、`envelope` は `value`・`name`、`ga4` は `value`・`name`・`parameters` |
| `includes` | 取り込んだカタログの `name` と `version` の並び。取り込んでいなければ `[]` |
| `events[].origin` | `common`（共通カタログの出来事）か `app`（アプリの出来事） |
| `events[].sentBy` | `package`（AnalyticsCore が送る）か `app` |
| `events[].parameters` | **YAML に書いた順**（列の割り当てはこの順）。`key`・`origin`・`type` は必ずある。`extend:` で足した引数は `origin: app` で後ろに付く。任意の引数には `"optional": true` が付き、`props` に無くてよい |
| `userProperties` | 属性。`token` は無い |
| `facts` | サーバーで数えるもの。照らし合わせには使わない |

引数（と属性）の `type` ごとの鍵と、受け口が通してよい値:

| `type` | 鍵 | 通してよい値（JSON） |
|---|---|---|
| `enum` | `values`・`extensible`（引数のときだけ）・`appValues`（共通の引数のときだけ。アプリが足した値） | `values` のどれかの文字列 |
| `bucket` | `edges`（昇順）・`values` | `values` のどれかの文字列（`AnalyticsValue.bucket(_:edges:)` が返しうる帯の名前の全部） |
| `token` | `pattern`・`maxLength` | 文字列で、長さが `maxLength` 以下、**全体が** `pattern` に合う |
| `flag` | — | `true` か `false` |
| `count` | — | 整数 |
| `number` | — | 有限の数 |

`AnalyticsBatchSink` が送る束の形は [common/ENVELOPE.md](common/ENVELOPE.md) の 1 つだけ。
出来事の引数は `events[].props` に、`--json` の `key` をそのまま鍵にして載る。

```json
{ "schema_version": 1, "app": "kotoakari", "install_id": "8c1f…", "app_version": "1.2.0", "build": "45",
  "channel": "appstore", "lang": "ja", "region": "JP", "sent_at": 1790000000000,
  "events": [ { "id": "…", "name": "block_seen", "occurred_at": 1789999990000,
                "props": { "render_id": "r_01J9ABCD", "position": "3_4" } } ] }
```

## --ts の形

`generate --ts` は、受け口（Cloudflare Worker・studio）が import する TypeScript を書き出す。中身は `--json` と同じで、
型として使える形にしてある。例は [example-common.catalog.ts](example-common.catalog.ts)。共通カタログだけのものは
[common/common.catalog.ts](common/common.catalog.ts)（と `common.catalog.json`）。

```ts
export const CATALOG_VERSION = 3 as const;
export const INCLUDES = [{ name: "common", version: 1 }] as const;

export const PaywallSource = ["onboarding", "settings", "limit", "entry_limit"] as const;   // enum の値
export type PaywallSource = (typeof PaywallSource)[number];

export const EVENTS = {
  paywall_shown: {
    kind: "impression", dedup: "always", origin: "common", sentBy: "app",
    parameters: {
      source: { type: "enum", origin: "common", values: PaywallSource, extensible: true },
      pw_id: { type: "token", origin: "common", pattern: "[a-f0-9]{8}", maxLength: 8 },
      ...
    },
  },
} as const;

export type EventName = keyof typeof EVENTS;
export const EVENT_NAMES: EventName[];
export const COMMON_EVENT_NAMES = [...] as const;          // origin が common の出来事
export interface EventProps {                               // 出来事ごとの props の型
  paywall_shown: { source: PaywallSource; pw_id: string; nth: "0" | "1_1" | ...; variant: Variant };
}
```

- enum の型名（`type_name`、無ければ鍵から作る名前）が、値の `const` と型の名前になる
- `bucket` は帯の名前の和、`token` は `string`、`count`・`number` は `number`、`flag` は `boolean`
- 引数の無い出来事は `Record<string, never>`
- enum の型名が `EVENTS`・`EventName`・`EventProps` などの出力の名前と重なると、書き出す前に落ちる
