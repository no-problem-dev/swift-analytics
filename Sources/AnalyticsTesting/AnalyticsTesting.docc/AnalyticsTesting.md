# ``AnalyticsTesting``

A recording destination for pinning which events a flow fires, in what order, and how many times.

## Overview

Import this module from test targets only. It contains one type.

``RecordingAnalytics`` conforms to `AnalyticsClient` and keeps everything it is handed, in order,
without deduplication of its own — so an assertion sees exactly what the layer above it produced.

Counting matters as much as naming. Analytics bugs are more often "fired too much" than "did not
fire", and a test that only checks that a name is present cannot see the difference. Assert on the
whole sequence, or on ``RecordingAnalytics/count(of:)``:

```swift
let analytics = RecordingAnalytics()
// exercise the flow
#expect(analytics.names == ["tutorial_begin", "tutorial_complete"])
#expect(analytics.count(of: "tutorial_begin") == 1)
```

When the parameters matter too, ``RecordingAnalytics/lines`` renders each event as
`name key=value key=value` with the keys sorted, which makes the expectation stable across runs —
dictionary order is not.

``RecordingAnalytics`` is a class marked `@unchecked Sendable`; its two mutable arrays are guarded
by a lock, so it is safe to hand to code running on another task. ``RecordingAnalytics/reset()``
clears both, which lets one instance serve several phases of a longer test.

To pin the deduplication behaviour of `DedupingAnalytics` itself, give it a `UserDefaults` suite of
its own — the `install` scope writes a flag there, and a shared suite leaks state between tests.

## Topics

### Recording

- ``RecordingAnalytics``
