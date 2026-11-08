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
| `lang`・`region` | 端末の言語と地域（`Locale.current`） |
| `sent_at`・`occurred_at` | UNIX 時刻のミリ秒（UTC）。秒や ISO 文字列は使わない |
| `events[].id` | 出来事ごとの UUID。再送で同じ物が2回届いても受ける側で1つにする |
| `events[].props` | 出来事の引数。値は文字列・数・真偽だけ（入れ子にしない） |

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
