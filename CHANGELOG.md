# Changelog

## [Unreleased]

One shared catalog and one envelope for every app. **Contains breaking changes** (see Removed and
Changed); 0.x minors break, so move from `.upToNextMinor(from: "0.2.0")` deliberately, following
"Migrating from 0.2" below.

### Added

- `Schema/common/common.yaml` — the common catalog: `first_open`, `internal_device`,
  `screen_viewed`, `tapped`, `onboarding_step`, `onboarding_completed`, `signed_in`,
  `experiment_assigned`, `paywall_*`, `purchase_completed`, `restore_completed`,
  `review_requested`, `whats_new_shown`, `whats_new_closed`. Generated copies for receivers in
  `Schema/common/common.catalog.json` and `common.catalog.ts`
- `Schema/common/ENVELOPE.md` — the one shape `AnalyticsBatchSink` sends
- Generator: `include: common` (in `dialect: envelope` catalogs) and `extend:`, which adds values to
  `extensible: true` enums and parameters to common events. Common values and parameters cannot be
  removed or retyped; trying fails generation. Values are added per type, so `ScreenName` gets them
  in every event that uses it. An app event can use a common enum by `type_name` alone.
  `--common <path>` reads another copy of the common catalog
- Generator: `dialect: envelope` — names and values as in `first_party` (snake_case, 40 / 64
  characters), with no column limits, since `props` is a flat JSON object
- Generator: `--ts` writes the catalog as TypeScript (`EVENTS`, `EventName`, `EventProps`, a
  `const` and a type per enum) for Workers and dashboards
- Generator: `--json` marks each event's and parameter's `origin` (`common` / `app`), each event's
  `sentBy` (`package` / `app`), `includes`, and for enums `extensible` and `appValues`
- Generator: `sent_by: package` in the common catalog keeps `first_open` and `internal_device`
  out of the app's Swift type; this package sends them
- Generator: the YAML reader takes flow mappings (`{ type: enum, values: [a, b] }`, nestable),
  `\\` and `\"` escapes in double quotes, and `''` in single quotes. Duplicate keys and other
  escapes are rejected, as is anything else outside the documented subset
- `InstallID`, `BuildChannel` (with the pure `resolve(…)`), `InternalDevice`, `CommonEvent`, and
  `FirstOpenKind` in `AnalyticsCore`
- `FirstLaunch.recordLaunch(sendingTo:hasPriorData:defaults:now:)` — stamps the first launch and
  sends `first_open{kind: fresh|upgraded}` once
- `EnvelopeContext` and `BatchTransport` in `AnalyticsBatchSink`

### Changed

- **BREAKING:** `AnalyticsBatchSink` posts the batch itself, in the fixed envelope. The initialiser
  is `init(app:endpoint:authorize:uid:directory:policy:context:transport:makeID:now:)`; responses are
  read by a fixed table (`2xx` delivered; `401`/`403`/`408`/`429`/`5xx` kept, honouring
  `Retry-After`; other statuses dropped). Every event gets an `id` (UUID) and `occurred_at` in ms.
  Events tracked under a different app version, build, or uid go in separate batches
- **BREAKING:** `AnalyticsBatchSink.setUserProperty(_:)` does nothing — the envelope has no place for
  properties
- **BREAKING:** the spool file is format 2; a 0.2 spool is not read (its events were laid out for
  another envelope)
- **BREAKING:** the generator rejects unknown top-level keys in a catalog
- `AnalyticsEvent.dedupKey` is a protocol requirement (with the same default). A `dedupKey` written
  on the conforming type now reaches `DedupingAnalytics`; before, it was silently ignored
- The generated `setUserProperty` overload is left out when a catalog declares no properties
- `purchase_completed` is documented as a client-side outcome (conversion per paywall); `facts` are
  for what only the server has. Revenue and renewals are RevenueCat's

### Removed

- **BREAKING:** `BatchFormat`, the `format`, `header`, `stamp` and `send` parameters of
  `AnalyticsBatchSink`, and the public `BatchOutcome`
- **BREAKING:** `FirstLaunch.markIfNeeded(defaults:now:)` — use `recordLaunch(sendingTo:)`

### Migrating from 0.2

1. Pin `.upToNextMinor(from: "0.3.0")`
2. In `analytics.yaml`, set `dialect: envelope` and `include: common`. Delete the events the
   common catalog now has (rename yours to its names: `paywall_viewed` → `paywall_shown`,
   `purchased` → `purchase_completed`, …) and put your extra values under `extend:`. Run
   `generate --out … --json … --ts …` and fix the call sites the compiler points at
3. Replace the sink: `AnalyticsBatchSink(app: "<snake_case name>", endpoint: <URL>, authorize: { <headers> })`,
   plus `uid:` if you tie behaviour to purchases. Drop `header`, `stamp`, `format`, `send`
4. Replace `FirstLaunch.markIfNeeded()` with `FirstLaunch.recordLaunch(sendingTo: analytics)`
   (`hasPriorData: true` when the app already holds data from before). Call
   `InternalDevice.mark(sendingTo: analytics)` from your hidden switch
5. Change the receiver to read the envelope (or create the `app_events` table in ENVELOPE.md), and
   check incoming names against the generated `catalog.ts`. Remove any `dedupKey` workaround

## [0.2.0] - 2026-10-01

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