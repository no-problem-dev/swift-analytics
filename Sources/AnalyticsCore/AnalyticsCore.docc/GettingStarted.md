# Getting Started

Declare the events you intend to measure, generate the Swift for them, and wire a destination in
one place.

## Write the catalog

The catalog is the only place an event is defined. It carries the name, the kind, the counting rule,
and the parameters — so a reviewer can see what you decided to measure without reading any call
sites.

```yaml
# analytics.yaml
version: 1
dialect: ga4
swift:
  event_type: AppEvent
  property_type: AppUserProperty

events:
  - name: onboarding_started
    kind: screen
    dedup: install
    description: The user reached the first onboarding screen

  - name: invite_share_opened
    kind: interaction
    dedup: always
    parameters:
      surface:
        type: enum
        values: [settings, empty_state, banner]

user_properties:
  - name: household_size
    type: enum
    values: ["1", "2", "3_plus"]
```

`kind` is one of ``EventKind``'s four cases and `dedup` is one of ``DedupScope``'s four. The full
grammar, including parameter types and the GA4 dialect rules, is specified in `Schema/SCHEMA.md` in
the repository.

## Generate the Swift

```sh
Scripts/analytics-gen.py generate \
  --schema analytics.yaml \
  --out Sources/App/Generated/AppAnalytics.swift
```

The generated file conforms `AppEvent` to ``AnalyticsEvent`` and `AppUserProperty` to
``AnalyticsUserProperty``, one enum case per declared event. Commit it: the diff is what a reviewer
reads when the measurement plan changes, and generating at build time hides that diff.

## Compose a destination

Build the chain once, at the composition root. ``DedupingAnalytics`` goes on the outside so that
everything below it sees only the sends that survived the counting rule.

```swift
import AnalyticsCore

#if DEBUG
let analytics = DedupingAnalytics(MultiplexAnalytics([ConsoleAnalytics(), vendor]))
#else
let analytics = DedupingAnalytics(vendor)
#endif
```

In a SwiftUI app, hand it to the view tree with the `analytics(_:)` modifier from
`AnalyticsSwiftUI`; the environment default is ``NoopAnalytics``, so previews and tests run
unconfigured.

## Fire

Interactions are sent directly:

```swift
@Environment(\.analytics) private var analytics

Button("Invite") {
    analytics.track(.inviteShareOpened(surface: .settings))
}
```

Screens and list rows are not. They go through the visibility rule described in
<doc:CountingRules>, using the `trackScreen(_:threshold:dwell:)` and
`trackImpression(_:threshold:dwell:)` modifiers from `AnalyticsSwiftUI`.

## Bucket anything numeric

A raw count can identify a person — there is exactly one user with 137 items. Use
``AnalyticsValue/bucket(_:edges:)`` to reduce a number to a band before it leaves the device:

```swift
AnalyticsValue.bucket(0,  edges: [1, 6, 16])   // "0"
AnalyticsValue.bucket(3,  edges: [1, 6, 16])   // "1_5"
AnalyticsValue.bucket(99, edges: [1, 6, 16])   // "16_plus"
```

Edges are lower bounds and are sorted before use. A value below the first edge is rendered as the
integer one less than that edge.

## Check it in CI

```sh
Scripts/analytics-gen.py check --schema analytics.yaml --out Sources/App/Generated/AppAnalytics.swift
Scripts/analytics-gen.py audit --schema analytics.yaml --sources Sources/
```

`check` fails when the committed Swift no longer matches the catalog. `audit` fails on three things
that review does not catch: an event, enum value, or user property that is declared but never fired;
the same event fired from two or more places; and a send that bypasses the generated API.

## Test without a destination

`AnalyticsTesting` provides `RecordingAnalytics`, which conforms to ``AnalyticsClient`` and keeps
everything it was handed, so an assertion can be written against names and rendered parameter lines
rather than against a network call.
