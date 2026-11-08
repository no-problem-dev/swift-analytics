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
``NoopAnalytics`` in previews, ``MultiplexAnalytics`` to fan out to several at once, and in release
builds either a vendor adapter such as `swift-analytics-firebase` or `AnalyticsBatchSink` for a
first-party receiver. ``AnalyticsSwitch`` goes in front of all of them, as the person's off switch.

What every app shares about its install lives here too: ``InstallID`` (the `install_id` of every
batch), ``BuildChannel`` (debug, TestFlight, or the App Store), ``FirstLaunch`` (which sends
`first_open` once), and ``InternalDevice`` (which marks the makers' own devices). The two events
this package sends itself are ``CommonEvent``; every other event comes from the app's generated
catalog, which includes the common one (`Schema/common/common.yaml`).

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
- ``AnalyticsSwitch``
- ``MultiplexAnalytics``
- ``ConsoleAnalytics``
- ``NoopAnalytics``

### The install and the build

- ``FirstLaunch``
- ``FirstOpenKind``
- ``InstallID``
- ``BuildChannel``
- ``InternalDevice``
- ``CommonEvent``
