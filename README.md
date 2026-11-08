English | [日本語](./README.ja.md)

# swift-analytics

Analytics events for Swift apps that declare how they should be counted, so the rule lives in the event's definition instead of in whoever remembers it at the call site.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20watchOS%2010%20%7C%20visionOS%201-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

This is not diagnostic logging (`swift-log` / `swift-metrics`). It records what people did, in a
shape you can analyse later.

Analytics bugs are more often "fires too much" than "does not fire", and neither is caught by types,
tests, review, or the dashboard. The usual cause is not that a call was written in two places — it
is that **the counting rule was written nowhere**, so nobody could call the second call site a
mistake. This package puts the counting rule in the vocabulary.

## Features

- **The catalog owns the counting rule.** "Once per install" and "once it has been visible for a
  second" are declared in YAML, not remembered at the call site
- **Swift is generated from that catalog.** There is no string-based send, so an event cannot be
  misspelled or fired with parameters nobody declared
- **Deduplication is enforced, not remembered.** `DedupingAnalytics` applies the declared scope;
  call sites never ask "did I already fire this"
- **Impressions have a definition that closes.** 50% of the area, continuously visible for 1.0
  second, and the tracker holds no clock — so the rule is pinned in a unit test, with no simulator
  and no real waiting
- **A CI audit that grep cannot do.** Declared-but-never-fired events, the same firing appearing in
  two places, and string sends that bypass the catalog all fail the build
- **One shared catalog, one envelope.** `Schema/common/common.yaml` holds the events every app has
  (`first_open`, `paywall_*`, `purchase_completed`, `review_requested`, `whats_new_*`, …). An app
  catalog says `include: common` and adds its own values with `extend:` instead of copying names.
  `AnalyticsBatchSink` sends every app's events in the same fixed envelope
  (`Schema/common/ENVELOPE.md`); the app gives it a URL, an authorization closure, and its name
- **The receiver gets the same catalog.** `--json` and `--ts` write the catalog for the server
  (a Cloudflare Worker, a dashboard) to check against and import
- **The install and the build, done once.** `InstallID`, `BuildChannel` (debug / TestFlight /
  App Store), `FirstLaunch` (sends `first_open{kind: fresh|upgraded}` once), and `InternalDevice`
  (marks the makers' own devices once)
- **An off switch that remembers.** `AnalyticsSwitch` drops everything while the person has turned
  measurement off, keeps that choice across launches, and erases what was buffered
- **Zero external dependencies.** Vendor SDKs (Firebase, PostHog) live in separate packages,
  because SwiftPM resolves dependencies per package. For your own server, the app writes the URL
  and the authentication
- **An on-device log viewer.** Read what was actually sent, with its kind, its counting rule, and a
  `×2` on anything that fired twice — no Mac attached

## Quick Start

Declare the event, and how it is counted:

```yaml
# analytics.yaml
version: 1
dialect: envelope
include: common             # first_open, paywall_*, review_requested, …
swift:
  event_type: AppEvent

extend:
  - name: screen_viewed
    parameters:
      screen:
        values: [home]      # add values to the shared enums marked extensible

events:
  - name: entry_saved
    kind: outcome           # screen | impression | interaction | outcome
    dedup: always           # session | install | always
    description: An entry was saved
```

Generate the Swift, and commit the result — a change to analytics is a change to *what you decided
to measure*, and the diff is the only review artifact:

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift \
  --json server/catalog.json --ts server/catalog.ts
```

Wire the destination once, at launch:

```swift
let sink = AnalyticsBatchSink(
    app: "kotoakari",
    endpoint: URL(string: "https://api.example.com/v1/events")!,
    authorize: { ["Authorization": "Bearer \(try await auth.idToken())"] }
)
let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) { await sink.purge() }
FirstLaunch.recordLaunch(sendingTo: analytics)
```

Then the whole call site is one modifier:

```swift
import AnalyticsSwiftUI

HomeView().trackScreen(.screenViewed(screen: .home))
```

## Documentation

The API reference and the guides (Getting Started, Counting Rules, What Not to Send) are the DocC catalogs under `Sources/*/*.docc/`. Open them in Xcode with Product › Build Documentation.

The catalog file format — including `include` / `extend`, the dialects, the `token` parameter type,
and the shape of the `--json` and `--ts` output — is specified, in Japanese, in
[Schema/SCHEMA.md](./Schema/SCHEMA.md). The envelope is [Schema/common/ENVELOPE.md](./Schema/common/ENVELOPE.md).

## Installation

```swift
.package(url: "https://github.com/no-problem-dev/swift-analytics.git", .upToNextMinor(from: "0.3.0"))
```

| Product | Contents | Depends on |
|---|---|---|
| `AnalyticsCore` | Vocabulary, ports, counting rules | nothing |
| `AnalyticsSwiftUI` | Firing from views, on-device log viewer | SwiftUI |
| `AnalyticsBatchSink` | Keeps events on the device and sends them in batches, in the fixed envelope, to your own server | `AnalyticsCore` |
| `AnalyticsTesting` | Test doubles | nothing |

Vendor adapters are separate packages — see
[swift-analytics-firebase](https://github.com/no-problem-dev/swift-analytics-firebase). Bundling one
here would pull a vendor SDK into consumers that only use the vocabulary.

The generator runs on Python 3 alone; there is nothing to install.

## Requirements

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+ / watchOS 10.0+ / visionOS 1.0+
- Swift 6.2+
- Python 3 (for the catalog generator only)

## License

MIT — see [LICENSE](LICENSE).
