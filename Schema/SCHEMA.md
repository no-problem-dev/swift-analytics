# analytics.yaml — 計測カタログの正典

アプリごとに 1 つ持つ。ここに書かれていない出来事は送れない。

**先にこのファイルを直してから実装する。** 逆順にすると、実装を読まないと何を測っているか
分からなくなり、エンジニア以外は計測の話に参加できなくなる。

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Generated/AppAnalytics.swift
Scripts/analytics-gen.py check    --schema analytics.yaml --out Generated/AppAnalytics.swift
Scripts/analytics-gen.py audit    --schema analytics.yaml --sources Sources/
```

- `generate` … Swift を書き出す。**人の手元で走らせ、生成物をコミットする**
- `check` … 生成物がスキーマとずれていたら落ちる。CI に置く
- `audit` … カタログにあるのに撃たれていない／同じ発火が 2 箇所にある、を落とす。CI に置く

---

## 全体

```yaml
version: 1
dialect: ga4          # 送信先の方言。名前と値の制約を生成時に検査する
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
    dedup: episode                 # episode | session | install | always
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

`enum` の値は `snake_case` で書く。Swift 側の case 名は自動で lowerCamelCase になり、
raw 値は書いたままが送られる。

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
| 方言の制約（`dialect: ga4` なら名前 40 字・パラメータ 25 個・値 100 字・予約語） | **破った送信は成功に見えて捨てられる** |
| `enum` 値が snake_case か | 送信先で値の集合が割れない |
| `kind: impression` なのに `dedup: always` のような噛み合わない組 | 数え方が種別と矛盾していないか |

`audit` は実装側を見る。

| 検査 | なぜ |
|---|---|
| カタログの全ケース・全値が 1 箇所以上から撃たれているか | 宣言だけ残ると、ダッシュボードの 0 が「使われていない」と読める |
| **同じ発火（引数まで込みで同じもの）が 2 箇所以上に無いか** | 1 回の閲覧で複数回撃つ事故は、テストでもレビューでも落ちない |
| 属性が 1 箇所以上から設定されているか | 宣言だけの属性はセグメントが空になる |
| 文字列直書きの送信が無いか | カタログを迂回されると検査が意味を失う |
