# ``AnalyticsSwiftUI``

Firing from a view tree, and reading back on the device what was actually sent.

## Overview

`AnalyticsSwiftUI` is the only module that knows about screens. It holds three things:

**A place for the destination.** The `analytics` environment value carries an
`AnalyticsClient`, and the `analytics(_:)` view modifier installs one at the root. The default is
`NoopAnalytics`, so previews and snapshot tests run without any wiring. It lives in the environment
rather than in a store because the things being measured — a screen appeared, a button was pressed —
are view events; putting it in a store would force a stateless screen to acquire one purely to
report.

**Two modifiers that apply the visibility rule.** `trackScreen(_:dwell:)` counts a screen once it
has been continuously on screen for a second, counts again after it leaves and returns, and does
not count while the app is in the background. It takes no area threshold: a screen has appeared or
it has not, so there is no fraction to compare.
`trackImpression(_:threshold:dwell:)` does the same for a row inside a scrollable container, driven
by `onScrollVisibilityChange`, and requires iOS 18 / macOS 15 / tvOS 18 / watchOS 11 / visionOS 2.

`trackImpression(_:threshold:dwell:)` deliberately does **not** fall back to `onAppear` outside a
scrollable container, because a lazy list delivers `onAppear` for rows that are still off screen —
which quietly mixes "was never visible" into the count of "was seen". Use
`trackScreen(_:dwell:)` when you mean the screen itself.

Neither modifier decides anything. Both forward to ``ImpressionSession``, which owns the tracker,
the pending wait, and the send — so re-entrant `onAppear`, early dismissal, backgrounding, and
scrolling past can be tested without rendering a view.

```swift
let session = ImpressionSession(event: event, client: recorder, sleep: { _ in })
session.appeared()
await session.settled()
session.appeared()                                  // SwiftUI re-entry
await session.settled()
#expect(recorder.count(of: "paywall_shown") == 1)   // still one
```

**An on-device reader.** Vendor debug consoles lag by hours and `os.Logger` needs a Mac attached,
which makes the most interesting case — what fires when the user returns from a notification —
the hardest one to observe. ``AnalyticsLog`` keeps the most recent sends in memory,
``LoggingAnalytics`` feeds it, and ``AnalyticsLogViewer`` shows them newest first with the name,
the parameters, the kind, the deduplication scope, and a repeat count.

Place ``LoggingAnalytics`` **inside** `DedupingAnalytics`, not outside it. Outside, suppressed sends
would appear in the list and read as "this fired twice" — the exact bug the list exists to find.

```swift
let log = AnalyticsLog()
let analytics = DedupingAnalytics(MultiplexAnalytics([LoggingAnalytics(log: log), vendor]))
```

``AnalyticsLog`` and ``ImpressionSession`` are main-actor isolated. ``AnalyticsLog`` keeps at most
`limit` entries — 200 by default — and discards the oldest.

## Topics

### Wiring

- ``SwiftUICore/EnvironmentValues/analytics``
- ``SwiftUICore/View/analytics(_:)``

### Counting a view

- ``SwiftUICore/View/trackScreen(_:dwell:)``
- ``SwiftUICore/View/trackImpression(_:threshold:dwell:)``
- ``ImpressionSession``

### Reading on device

- ``AnalyticsLog``
- ``LoggingAnalytics``
- ``AnalyticsLogViewer``
