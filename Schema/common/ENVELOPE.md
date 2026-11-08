# 封筒（Envelope）— 送る形は1つだけ

`AnalyticsBatchSink` が送る JSON はこの形に固定する。キーの名前・時刻の単位を変える設定は持たない
（0.2 までの `BatchFormat` でキーを選べたことが、アプリごとに7通りの形に分かれた原因だった）。
送り先（自前のサーバーの URL）と、そこへ付ける認証だけをアプリが渡す。

```json
{
  "schema_version": 1,
  "app": "kotoakari",
  "install_id": "8c1f…（UUID・インストールごと・端末に保存）",
  "uid": "Firebase の uid（無ければ省く）",
  "app_version": "1.2.0",
  "build": "45",
  "channel": "debug | testflight | appstore",
  "lang": "ja",
  "region": "JP",
  "sent_at": 1762560000000,
  "events": [
    { "id": "UUID", "name": "paywall_shown", "occurred_at": 1762559990000, "props": { "source": "onboarding" } }
  ]
}
```

| キー | 決まり |
|---|---|
| `schema_version` | この封筒の形の版。形を変えたら上げる。カタログの版（catalogVersion）とは別 |
| `app` | アプリの短い名前（snake_case）。受ける側の表で製品を分ける |
| `install_id` | `InstallID` が作って端末に保存する UUID。消して入れ直すと変わる |
| `uid` | サインインしていれば Firebase の uid。行動と課金を結ばないアプリは送らない |
| `app_version`・`build` | `CFBundleShortVersionString`・`CFBundleVersion` |
| `channel` | `BuildChannel`。Debug ビルド・TestFlight（sandbox のレシート）・App Store |
| `lang` | 端末の言語。BCP 47 の言語の札で、地域は含めない（`ja`・`en`・`zh-Hans`・`zh-Hant`・`sr-Latn`）。中国語はいつも文字（`Hans`・`Hant`）を付け、ほかの言語はふだんと違う文字のときだけ付ける（`EnvelopeContext.languageTag(of:)`）。0.3.0 は言語の2文字だけで、簡体字と繁体字が同じ `zh` だった |
| `region` | 端末の地域（`Locale.current.region`。`JP`） |
| `sent_at`・`occurred_at` | UNIX 時刻のミリ秒（UTC）。秒や ISO 文字列は使わない。`occurred_at` は track した時刻か、`occurred(at:)` で作った出来事ならその時刻（溜めてから送る出来事のため） |
| `events[].id` | 出来事ごとの UUID。再送で同じ物が2回届いても受ける側で1つにする |
| `events[].props` | 出来事の引数。値は文字列・数・真偽だけ（入れ子にしない） |

- `app_version`・`build`・`uid` は**出来事が起きたときの値**。`AnalyticsBatchSink` は、これが違う出来事を別の束で送る
  （更新の前に溜めた出来事を、更新の後の版で送らない）
- 共通の出来事の enum の値は、アプリが足すことがある（`extend:`・[SCHEMA.md](../SCHEMA.md) の extensible）。受ける側は知っている値だけで決める:
  `first_open.kind` は `fresh` だけを新規と読み、ほか（`upgraded`・アプリが足した `existing` など）は前から使っていた人として扱う
- 利用者の属性（`AnalyticsUserProperty`）は封筒に載らない。プランなどの状態はサーバー（購入は RevenueCat）が正本
- 受け口の応答の読み方は固定: `2xx` は届いた・`401`・`403`・`408`・`429`・`5xx` は残して後で送る（`Retry-After` を守る）・ほかは捨てる

## 受ける側の表（D1）

新しく作るアプリはこの表をそのまま使う。既にあるアプリは自分の表のまま受けてよい（受け口で封筒を自分の列に移す）。

```sql
CREATE TABLE app_events (
  id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  uid TEXT,
  name TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,   -- ms
  props TEXT NOT NULL DEFAULT '{}',
  app_version TEXT, build TEXT, channel TEXT, lang TEXT, region TEXT,
  schema_version INTEGER NOT NULL,
  received_at INTEGER NOT NULL    -- ms
);
CREATE INDEX app_events_name_time ON app_events(name, occurred_at);
CREATE INDEX app_events_install ON app_events(install_id, occurred_at);
```
