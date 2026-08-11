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
- **Zero external dependencies.** Vendor SDKs (Firebase, PostHog, your own server) live in separate
  packages, because SwiftPM resolves dependencies per package
- **An on-device log viewer.** Read what was actually sent, with its kind, its counting rule, and a
  `×2` on anything that fired twice — no Mac attached

## Quick Start

Declare the event, and how it is counted:

```yaml
# analytics.yaml
version: 1
dialect: ga4
swift:
  event_type: AppEvent

events:
  - name: paywall_shown
    kind: impression        # screen | impression | interaction | outcome
    dedup: episode          # episode | session | install | always
    description: The paywall was actually seen
```

Generate the Swift, and commit the result — a change to analytics is a change to *what you decided
to measure*, and the diff is the only review artifact:

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
```

Then the whole call site is one modifier:

```swift
import AnalyticsSwiftUI

PaywallView().trackScreen(.paywallShown)
```

## Documentation

[**API reference and guides**](https://no-problem-dev.github.io/swift-analytics/documentation/) —
including [Getting Started](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/gettingstarted/),
[Counting Rules](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/countingrules/),
and [What Not to Send](https://no-problem-dev.github.io/swift-analytics/documentation/analyticscore/whatnottosend/).

The catalog file format is specified, in Japanese, in [Schema/SCHEMA.md](./Schema/SCHEMA.md).

## Installation

```swift
.package(url: "https://github.com/no-problem-dev/swift-analytics.git", .upToNextMinor(from: "0.1.0"))
```

| Product | Contents | Depends on |
|---|---|---|
| `AnalyticsCore` | Vocabulary, ports, counting rules | nothing |
| `AnalyticsSwiftUI` | Firing from views, on-device log viewer | SwiftUI |
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
