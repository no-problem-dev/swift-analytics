# What Not to Send

Domain facts and free-form strings stay out of the event stream, and the architecture is better for it.

## Overview

``EventKind`` has four cases — a screen was reached, an element was seen, something was pressed,
something finished. There is no case for "purchased", "household created", or "notification sent".
The omission is deliberate.

## Facts belong to the server

A domain fact is already persisted on the server, and that record is the source of truth. Sending
the same fact as an event guarantees that the two will disagree, with no way to adjudicate: an
action recorded offline and synced later has an occurrence time that differs from its send time, so
neither series can be corrected against the other.

Count facts with SQL against the server's data. Keep the event stream for the things only the
client knows: what was on screen, what was touched, what was abandoned.

The practical payoff is architectural. Because facts are not events, **no analytics call has to be
threaded into the use-case layer.** Instrumentation lives at the surface, where the surface-level
things it measures actually happen, and stops parasitising the parts of the app that would
otherwise have to carry it.

## Parameters carry enumerations and numbers

``AnalyticsValue`` admits four cases: an enumeration's raw value, an integer count, a floating
point number, and a boolean. Anything else does not compile, which is the point — a destination
that cannot represent a type discards it silently. GA4, for example, accepts neither arrays nor
dictionaries; the send reports success and the parameter simply never appears in the dashboard.

Human-written strings do not go in ``AnalyticsValue/text(_:)``. Product names, display names, email
addresses, and invite codes have no aggregate to contribute to, and once sent they cannot be
recalled. Use the raw value of a closed enumeration instead, so that the set of possible values is
reviewable in the catalog.

## Raw counts identify people

A count is not automatically safe. At a fine enough granularity it names an individual: there is
exactly one user with 137 items. ``AnalyticsValue/bucket(_:edges:)`` reduces a number to a band
before it leaves the device, which is almost always what the aggregate needed anyway.

```swift
AnalyticsValue.bucket(3, edges: [1, 6, 16])   // "1_5"
```

## User properties are state, not history

``AnalyticsUserProperty`` describes how things are right now, not what changed. Because setting the
same value twice has no effect, there is no transition to follow and no ordering to preserve — set
it wherever the state is known. That is also why ``DedupingAnalytics`` does not suppress repeated
property writes: suppression would leave a stale value in place after a restore.
