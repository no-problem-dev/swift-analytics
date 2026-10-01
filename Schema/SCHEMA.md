# analytics.yaml — 計測カタログの正典

アプリごとに 1 つ持つ。ここに書かれていない出来事は送れない。

**先にこのファイルを直してから実装する。** 逆順にすると、実装を読まないと何を測っているか
分からなくなり、エンジニア以外は計測の話に参加できなくなる。

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json]
Scripts/analytics-gen.py check    --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json]
Scripts/analytics-gen.py audit    --schema analytics.yaml --sources Sources/
```

- `generate` … Swift を書き出す。`--json` を付けると、受け口（サーバー）が照らし合わせに使う JSON も書き出す
  （下の「--json の形」）。`--out` と `--json` はどちらか一方だけでもよい。**人の手元で走らせ、生成物をコミットする**
- `check` … 生成物（渡した方の全部）がスキーマとずれていたら落ちる。CI に置く
- `audit` … カタログにあるのに撃たれていない／同じ発火が 2 箇所にある、を落とす。CI に置く

---

## 全体

```yaml
version: 1            # カタログの版。受け口と食い違いうる変更をしたら上げる（--json の catalogVersion）
dialect: ga4          # 送信先の方言（ga4 | first_party）。名前と値の制約を生成時に検査する
swift:
  event_type: StockEvent           # 生成する enum の名前
  property_type: StockUserProperty
  module: StockAnalytics           # 生成物を置くモジュール名（doc コメントに出るだけ）
  swiftui: true                    # trackScreen / trackImpression の型付き口も生成する

events: [...]
user_properties: [...]
facts: [...]          # 任意。サーバーから数えるもの。**Swift は生成されない**
```

## events

```yaml
events:
  - name: paywall_shown            # 送信先へ送る名前。snake_case
    case: paywallShown             # 任意。省略時は name から lowerCamelCase を作る
    kind: impression               # screen | impression | interaction | outcome
    dedup: always                  # session | install | always
    description: ふたりプランの案内が実際に見えた
    trigger: PaywallView が 50% 以上 1 秒       # 任意。どこで撃つかの申し送り
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
| `bucket` | `Int` を受け取り帯に落とす | 生の件数を送らないための型。`edges: [1, 6, 16]` |
| `token` | 生成される入れ子の struct（`init?(_:)`） | **サーバーが作った不透明な値**（`render_id`）と、**意味で決めたキー**（`place:ChIJ…`）だけ。出来事の引数にだけ使え、属性には使えない |

`enum` の値は `snake_case` で書く。Swift 側の case 名は自動で lowerCamelCase になり、
raw 値は書いたままが送られる。

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

| | `ga4` | `first_party` |
|---|---|---|
| 送り先 | Firebase Analytics（`swift-analytics-firebase`） | 自前の受け口（`AnalyticsBatchSink` で溜めて送る） |
| 名前（出来事・属性） | 40 字まで・英字で始まる英数字と `_`・予約接頭辞（`firebase_` `google_` `ga_`）と予約イベント名を落とす | 40 字まで・`snake_case`。引数の名前も同じ |
| 引数の数 | 25 個まで | **次元（`enum`・`flag`・`bucket`）4 つ・数（`count`・`number`）1 つ・`token` 2 つ**まで |
| 値（`enum` の値・`token` の長さ） | 100 字まで | 64 字まで |

`first_party` の引数の数は、受け口が 1 件を固定の列（名前・種別・次元 4・token 2・数 1）に書くことから来る。
受け口は、次元を**カタログに書いた順に** 1〜4 番目の列へ置く。

`audit` は実装側を見る。

| 検査 | なぜ |
|---|---|
| カタログの全ケース・全値が 1 箇所以上から撃たれているか | 宣言だけ残ると、ダッシュボードの 0 が「使われていない」と読める |
| **同じ発火（引数まで込みで同じもの）が 2 箇所以上に無いか** | 1 回の閲覧で複数回撃つ事故は、テストでもレビューでも落ちない |
| **`kind` に合った撃ち方をしているか**（`screen`→`trackScreen` / `impression`→`trackImpression` / `interaction`・`outcome`→`track`） | 表示を 1 露出 1 回に留めるのはこの 2 つだけ。`track()` で撃つと、その規則がどこにも掛からない |
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
| `limits` | 方言の上限。`first_party` は `value`・`name`・`dimensions`・`numbers`・`tokens`、`ga4` は `value`・`name`・`parameters` |
| `events[].parameters` | **YAML に書いた順**（列の割り当てはこの順）。`key` と `type` は必ずある |
| `userProperties` | 属性。`token` は無い |
| `facts` | サーバーで数えるもの。照らし合わせには使わない |

引数（と属性）の `type` ごとの鍵と、受け口が通してよい値:

| `type` | 鍵 | 通してよい値（JSON） |
|---|---|---|
| `enum` | `values` | `values` のどれかの文字列 |
| `bucket` | `edges`（昇順）・`values` | `values` のどれかの文字列（`AnalyticsValue.bucket(_:edges:)` が返しうる帯の名前の全部） |
| `token` | `pattern`・`maxLength` | 文字列で、長さが `maxLength` 以下、**全体が** `pattern` に合う |
| `flag` | — | `true` か `false` |
| `count` | — | 整数 |
| `number` | — | 有限の数 |

`AnalyticsBatchSink` の既定の形（`BatchFormat.standard`）では、束はこう届く。頭の項目はアプリが
`header` に渡したものと属性で、パッケージは中身を決めない。

```json
{ "v": 1, "catalog": 1, "install": "ins_…", "plan": "free",
  "events": [ { "id": "…", "name": "block_seen", "at": 1790000000.0,
                "params": { "render_id": "r_01J9ABCD", "position": "3_4" } } ] }
```
