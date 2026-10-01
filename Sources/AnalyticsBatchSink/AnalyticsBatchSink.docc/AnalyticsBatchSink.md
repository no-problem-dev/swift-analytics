# ``AnalyticsBatchSink``

A destination that keeps occurrences in a file on the device and sends them to your own server in
batches, through a closure the app writes.

## Overview

`AnalyticsBatchSink` is for apps that send measurement to a first-party receiver instead of a
vendor SDK. It depends on `AnalyticsCore` alone and knows nothing about HTTP: it keeps, it batches,
and it tries again. The URL, authentication, and how a response is read stay in the app, in one
closure that posts a body and maps the response onto a ``BatchOutcome``.

```swift
let sink = AnalyticsBatchSink(
    directory: appSupport.appending(path: "AppData/events"),
    header: { ["v": .count(1), "catalog": .count(1), "install": .text(await installID())] },
    stamp: { _, at in ["sinceInstallDays": .count(FirstLaunch.daysSince(now: at))] },
    send: { body in
        let (_, response) = try await session.upload(for: request, from: body)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return .delivered
        case 400, 413: return .rejected
        default: return .retryLater(after: nil)
        }
    }
)
let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) { await sink.purge() }
```

Call ``AnalyticsBatchSink/flush()`` after launch and when the scene moves to the background. The
sink also flushes by itself once ``BatchPolicy/flushThreshold`` events are waiting, and never starts
an attempt within ``BatchPolicy/minimumInterval`` of the previous one. Nothing here wakes the
device or schedules background work.

Pair it with a catalog written in the `first_party` dialect (`Schema/SCHEMA.md`), whose limits —
four dimensions, one number, two tokens, 64-character values — are the shape such a receiver stores,
and generate the receiver's copy of the catalog with `analytics-gen.py generate --json`.

## Topics

### Sending

- ``AnalyticsBatchSink``
- ``BatchOutcome``
- ``FlushReport``

### Shaping batches

- ``BatchPolicy``
- ``BatchFormat``
