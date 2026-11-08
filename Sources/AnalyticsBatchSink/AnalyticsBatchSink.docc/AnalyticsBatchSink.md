# ``AnalyticsBatchSink``

A destination that keeps occurrences in a file on the device and sends them to your own server in
batches, always in one envelope.

## Overview

`AnalyticsBatchSink` is for apps that send measurement to a first-party receiver instead of a
vendor SDK. It depends on `AnalyticsCore` alone. It keeps, it batches, it posts, and it tries
again — and the shape of what it posts is fixed (`Schema/common/ENVELOPE.md`). The app hands over
where to send, how to authorize, and its own name:

```swift
let sink = AnalyticsBatchSink(
    app: "kotoakari",
    endpoint: URL(string: "https://api.example.com/v1/events")!,
    authorize: { ["Authorization": "Bearer \(try await auth.idToken())"] }
)
let analytics = AnalyticsSwitch(DedupingAnalytics(sink)) { await sink.purge() }
FirstLaunch.recordLaunch(sendingTo: analytics)
```

Each batch carries `schema_version`, `app`, `install_id` (`InstallID`), `uid` when
there is one, `app_version`, `build`, `channel` (`BuildChannel`), `lang`, `region`,
and `sent_at` in milliseconds; each event carries `id`, `name`, `occurred_at` in milliseconds, and
`props`. Up to 0.2 the keys and the unit of time could be chosen, and the apps ended up with seven
shapes; now there is nothing to choose.

Call ``AnalyticsBatchSink/flush()`` after launch and when the scene moves to the background. The
sink also flushes by itself once ``BatchPolicy/flushThreshold`` events are waiting, and never starts
an attempt within ``BatchPolicy/minimumInterval`` of the previous one. Nothing here wakes the
device or schedules background work.

## The outcome of a batch

| Response | The batch |
|---|---|
| `2xx` | Removed from the spool |
| `401`, `403`, `408`, `429`, `5xx` | Kept, and not tried again before `Retry-After` (or ``BatchPolicy/minimumInterval``) |
| Any other status | Thrown away — sending it again would only be refused again |
| No response, or `authorize` threw | Kept |

Pair it with a catalog in the `envelope` dialect that includes the common catalog
(`Schema/SCHEMA.md`), and generate the receiver's copy with `analytics-gen.py generate --json --ts`.

## Topics

### Sending

- ``AnalyticsBatchSink``
- ``FlushReport``

### Shaping batches

- ``BatchPolicy``
- ``EnvelopeContext``
- ``BatchTransport``
