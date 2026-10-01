# Changelog

## [Unreleased]

Adds a first-party pipeline next to the vendor adapters: a sink that keeps events on the device
and sends them in batches through a closure the app writes, an off switch that remembers the
person's choice, and a generator dialect for a receiver of your own. **Contains breaking changes**
(see Removed and Changed); consumers on `from: "0.1.0"` will pick this version up automatically, so
pin `.upToNextMinor(from: "0.1.0")` before it is published, then move deliberately.

### Added

- `AnalyticsBatchSink` — a new product (depends on `AnalyticsCore` only). Keeps occurrences in a
  JSON file in a directory you give it, gives each one an ID and the time it happened, and sends
  batches (100 events / 64 KB by default) through `@Sendable (Data) async throws -> BatchOutcome`.
  Keeps at most 500 (oldest dropped first), sends itself at 100, and never starts an attempt within
  60 seconds of the last one. `BatchOutcome.rejected` drops the batch; `.retryLater(after:)` and a
  thrown error keep it. The latest user properties go in the head of every batch. `header` and
  `stamp` closures add the app's own fields; `BatchFormat` renames the keys (and switches the time
  to milliseconds) for receivers that already exist. `flush()`, `purge()`, `save()`, `pendingCount`
- `AnalyticsSwitch` (`AnalyticsCore`) — the person's off switch. Drops every event and property
  while off, keeps the choice in `UserDefaults` (`analytics.sendingEnabled`) so it survives
  relaunch, defaults to on (opt-out; `enabledByDefault: false` for opt-in), and runs an `onDisable`
  closure to erase what was buffered. Place it outside `DedupingAnalytics`
- Generator: `dialect: first_party` — names up to 40 characters in `snake_case` (parameter keys
  too), at most 4 dimensions (`enum` / `flag` / `bucket`), 1 number (`count` / `number`) and
  2 tokens per event, values up to 64 characters
- Generator: the `token` parameter type, for opaque server-made values and semantic keys. Declared
  with a `pattern` (whole-value match) and an optional `max_length`; generates a struct with a
  failable `init?(_:)`, so only well-formed values can be sent
- Generator: `--json` on `generate` and `check` writes (and checks) the catalog as JSON for a
  receiver to validate against — event names, kinds, dedup scopes, parameters in catalog order with
  their allowed values (bucket labels included), user properties, and facts. Shape documented in
  `Schema/SCHEMA.md`; example in `Schema/example-first-party.catalog.json`
- `ImpressionTracker.visible(_:)` — takes a visibility that has already been decided
- Generator tests (`Scripts/tests/`, Python standard library), also run by `swift test`

### Changed

- **BREAKING:** the generator now rejects parameter keys containing the words `name`, `email`,
  `place`, `text`, `title` or `address` (split on `_`; `placement` passes, `place_name` does not),
  in every dialect
- **BREAKING:** the generator rejects an unknown `dialect` instead of skipping its checks
- **BREAKING:** `trackScreen(_:threshold:dwell:)` is now `trackScreen(_:dwell:)`. A whole screen
  has no fraction to compare, and a threshold above 1.0 silently stopped the event
- **BREAKING:** the generator's `audit` requires the firing mechanism to match the kind
  (`screen` → `trackScreen`, `impression` → `trackImpression`, the rest → `track`)
- `AnalyticsLogViewer`'s built-in strings are English
- `DedupingAnalytics` and `RecordingAnalytics` are checked `Sendable` (their state lives in an
  `OSAllocatedUnfairLock`) instead of `@unchecked Sendable`

### Removed

- **BREAKING:** `DedupScope.episode`. It was handled exactly like `.always` and enforced nowhere;
  per-exposure counting is done by `trackScreen` / `trackImpression`. Catalogs that say
  `dedup: episode` fail to generate: use `always`, and regenerate


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