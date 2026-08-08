English | [日本語](./README.md)

# swift-analytics

Vocabulary for product analytics, and the tools to **count correctly** in SwiftUI.

This is not diagnostic logging (`swift-log` / `swift-metrics`). It is for recording what people
did, in a shape you can analyse later.

- **Zero external dependencies.** No vendor SDK (Firebase / PostHog / your own server) lives here
- **The catalog owns the counting rule.** Call sites never write "once per install" or "once it has been visible for a second"
- **Swift is generated from a YAML catalog.** There is no string-based API for sending events

## Why

Analytics bugs are more often "fires too much" than "does not fire" — and neither is caught by
types, tests, review, or the dashboard.

In one app the onboarding-start event was fired from both the consent screen and the flow itself,
so it landed twice per install. The completion rate looked like half of what it was, and
**everything was green with plausible-looking numbers on the dashboard**.

The cause was not that the call was written in two places. It was that **"once per install" was
written nowhere**, so nobody could call the second call site a mistake.

So the counting rule became part of the vocabulary.

## Installation

```swift
.package(url: "https://github.com/no-problem-dev/swift-analytics.git", from: "0.1.0")
```

| Product | Contents | Depends on |
|---|---|---|
| `AnalyticsCore` | Vocabulary, ports, counting rules | nothing |
| `AnalyticsSwiftUI` | Firing from views, on-device log viewer | SwiftUI |
| `AnalyticsTesting` | Test doubles | nothing |

Vendor adapters live in separate packages
([swift-analytics-firebase](https://github.com/no-problem-dev/swift-analytics-firebase)).
**They are not shipped here because SwiftPM resolves dependencies per package** — bundling one
would pull a vendor SDK into consumers that only use the vocabulary.

## Usage

### 1. Write the catalog

```yaml
# analytics.yaml
version: 1
dialect: ga4
swift:
  event_type: AppEvent
  property_type: AppUserProperty

events:
  - name: paywall_shown
    kind: impression        # screen | impression | interaction | outcome
    dedup: episode          # episode | session | install | always
    description: The paywall was actually seen
    parameters:
      source:
        type: enum
        values: [teaser, solo_card, gate_402]
```

Full spec: [Schema/SCHEMA.md](./Schema/SCHEMA.md).

### 2. Generate

```sh
Scripts/analytics-gen.py generate --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
```

**Commit the generated file.** A change to analytics is a change to *what you decided to measure*,
and **the diff is the only review artifact**. Generating at build time hides it.

Runs on Python 3 alone — nothing to install.

### 3. Wire it up

```swift
let analytics = DedupingAnalytics(
    MultiplexAnalytics([ConsoleAnalytics(), FirebaseAnalyticsClient()])
)

ContentView().analytics(analytics)
```

### 4. Fire

```swift
PaywallView()
    .trackScreen(.paywallShown(source: .settings))   // once 50% has been visible for 1s

Button("Invite") {
    analytics.track(.inviteShareOpened)
}
```

Call sites never check "did I already fire this" — `DedupingAnalytics` and `ImpressionTracker`
enforce the catalog's `dedup`.

### 5. Guard it in CI

```sh
Scripts/analytics-gen.py check --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
Scripts/analytics-gen.py audit --schema analytics.yaml --sources Sources/
```

`audit` fails on:

- Events, enum values or user properties declared but never fired (a zero on the dashboard reads as "nobody used it")
- **The same firing appearing in two or more places** — invisible to grep
- String-based sends that bypass the catalog

## What "seen" means

```
50% of the area, continuously visible for 1.0 second
```

This follows the MRC mobile in-app viewability guideline — not because it is a standard, but
because **the definition does not close without a time component**. Area alone cannot exclude a
flash, which leaves the `onAppear` hole exactly where it was.

`ImpressionTracker` owns the decision and **holds no clock**. It only answers "wait this long",
so the counting rule is pinned without a simulator or real waiting.

```swift
var tracker = ImpressionTracker()
#expect(tracker.visibility(1.0) == .startDwell(1.0))
#expect(tracker.visibility(0.0) == .cancelDwell)
#expect(tracker.dwellCompleted() == false)   // gone after 0.9s → not counted
```

## Facts are not sent

Domain facts ("purchased", "household created", "notification sent") **are not sent from the
client**. They are already persisted on the server, and that is the source of truth.

Sending them twice guarantees disagreement with no way to adjudicate — records made offline and
synced later have a different occurrence time than send time. Count them with SQL instead.

The payoff: **no analytics code in your use-case layer.** Instrumentation stops parasitising the
architecture.

## Checking on device

Vendor debug views lag, and `os.Logger` needs a Mac attached. **Events fired when returning from
a notification are hard to reproduce with Xcode attached**, so there is an on-device reader.

```swift
NavigationLink("Analytics log") { AnalyticsLogViewer(log: log) }
```

## License

MIT
