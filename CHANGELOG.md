# Changelog

Keep a Changelog 形式。バージョンはタグと一致させる。

## [0.1.0] - 2026-08-09

最初の公開。

### 入っているもの

- `AnalyticsCore` — 語彙（`AnalyticsEvent` / `AnalyticsUserProperty` / `AnalyticsValue`）、
  ポート（`AnalyticsClient`）、数え方（`EventKind` / `DedupScope` / `ImpressionTracker` /
  `DedupingAnalytics`）。**外部依存ゼロ**
- `AnalyticsSwiftUI` — `\.analytics` 環境値、`trackScreen` / `trackImpression`、
  `ImpressionSession`、端末で読む `AnalyticsLogViewer`
- `AnalyticsTesting` — `RecordingAnalytics`（回数まで数える）
- `Scripts/analytics-gen.py` — YAML のカタログから Swift を生成し、方言と配線を検査する
  （Python 標準ライブラリのみ）
- `Example/` — 繋ぎを実際に動かして確かめるサンプルアプリと XCUITest（`Example/HAZARDS.md`）

### 決めていること

- 「見えた」= 面積の 50% 以上が連続 1.0 秒以上（MRC のモバイルアプリ内表示基準）
- ドメインの事実はクライアントから送らない。サーバーの正典から数える
- 送信先のアダプタは同梱しない（SwiftPM の依存解決はパッケージ単位のため）
