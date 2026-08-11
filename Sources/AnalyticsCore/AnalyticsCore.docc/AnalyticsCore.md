# ``AnalyticsCore``

The vocabulary for product analytics: what an event is, what may ride on it, and how often it counts.

## Overview

`AnalyticsCore` has no dependency outside the standard library and Foundation, so it is safe to
import from a domain or use-case layer. It defines three things and nothing else:

- **What an event is.** ``AnalyticsEvent`` gives an event a name, typed parameters, a kind, and a
  deduplication scope. Conforming types are generated from a YAML catalog, so there is no
  string-based send anywhere in the API.
- **What may ride on an event.** ``AnalyticsValue`` admits four cases and refuses everything else,
  because a destination that cannot represent a type discards it silently — the send succeeds and
  the number never appears.
- **How often an event counts.** ``EventKind`` says what sort of thing happened; ``DedupScope`` says
  over what window a repeat is the same occurrence. Both are declared in the catalog, and
  ``DedupingAnalytics`` enforces them so that no call site has to remember.

Sending is a port, not an implementation. ``AnalyticsClient`` has two methods, and the concrete
destinations are supplied by the composition root: ``ConsoleAnalytics`` during development,
``NoopAnalytics`` in previews, ``MultiplexAnalytics`` to fan out to several at once, and a vendor
adapter such as `swift-analytics-firebase` in release builds.

The two rules that make the numbers trustworthy are written up separately:
<doc:CountingRules> explains what "seen" means and how each deduplication scope behaves, and
<doc:WhatNotToSend> explains why domain facts and free-form strings stay out of the stream.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CountingRules>
- <doc:WhatNotToSend>

### Describing an event

- ``AnalyticsEvent``
- ``AnalyticsUserProperty``
- ``AnalyticsValue``

### Counting

- ``EventKind``
- ``DedupScope``
- ``DedupingAnalytics``
- ``ImpressionTracker``

### Sending

- ``AnalyticsClient``
- ``MultiplexAnalytics``
- ``ConsoleAnalytics``
- ``NoopAnalytics``

### Install age

- ``FirstLaunch``
