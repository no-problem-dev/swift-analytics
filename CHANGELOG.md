# Changelog

## [Unreleased]


Keep a Changelog format. Versions match their tags.

## [0.1.0] - 2026-08-09

First public release.

### What's included

- `AnalyticsCore` — the vocabulary (`AnalyticsEvent` / `AnalyticsUserProperty` / `AnalyticsValue`),
  the port (`AnalyticsClient`), and how things are counted (`EventKind` / `DedupScope` /
  `ImpressionTracker` / `DedupingAnalytics`). **No external dependencies**
- `AnalyticsSwiftUI` — the `\.analytics` environment value, `trackScreen` / `trackImpression`,
  `ImpressionSession`, and `AnalyticsLogViewer` for reading logs on the device
- `AnalyticsTesting` — `RecordingAnalytics` (counts occurrences)
- `Scripts/analytics-gen.py` — generates Swift from the YAML catalog and checks the dialect
  and the wiring (Python standard library only)
- `Example/` — a sample app and XCUITest that run the wiring for real to check it (`Example/HAZARDS.md`)

### Decisions

- "Seen" = at least 50% of the area for at least 1.0 continuous second (the MRC in-app mobile
  viewability standard)
- Domain facts are not sent from the client. They are counted from the server's canonical record
- Adapters for destinations are not bundled (SwiftPM resolves dependencies per package)