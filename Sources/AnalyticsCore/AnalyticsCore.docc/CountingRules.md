# Counting Rules

What "seen" means, what each deduplication scope covers, and which layer enforces which.

## Overview

Two questions decide whether a number is trustworthy: *when does an exposure count as one view*,
and *over what window is a repeat the same occurrence*. Both are declared in the catalog rather
than remembered at the call site, so a second call site is a check failure instead of an argument.

## Why `onAppear` is not a view

`onAppear` does not mean a person saw something. It fires again whenever the view's identity
changes, never fires again when it does not, and fires for a frame that flickered past in 50
milliseconds. In a lazy list it also fires for rows that are still off screen. None of that is
related to how many times something was seen, and narrowing it with a `@State` flag only narrows it
to the lifetime of a view — which is not the lifetime of a viewing.

## The definition

``ImpressionTracker`` adopts the MRC mobile in-app viewability rule:

> **At least 50% of the area, continuously visible for at least 1.0 second, counts once.**

The point is not that it is an industry standard. It is that **the definition does not close
without a time component.** Area alone cannot exclude a flash, so the `onAppear` hole stays exactly
where it was and the person who read the paywall is counted the same as the person it flickered
past.

Both numbers are constructor parameters, so a surface with different requirements can raise or
lower them.

## The tracker holds no clock

``ImpressionTracker`` never sleeps and never reads the current time. It is a value type that
answers with an ``ImpressionTracker/Action``: start waiting this long, cancel the wait, or do
nothing. Waiting is the caller's job.

That is what makes the rule testable without a simulator and without real elapsed time:

```swift
var tracker = ImpressionTracker()
#expect(tracker.visibility(1.0) == .startDwell(1.0))
#expect(tracker.visibility(0.0) == .cancelDwell)
#expect(tracker.dwellCompleted() == false)   // gone after 0.9s, so not counted
```

Backgrounding is handled the same way: the tracker is told the scene became inactive and cancels
the pending wait, so an app that goes to the background mid-dwell does not accumulate a view.

## The wiring is where accidents happen

The definition is easy; the wiring is not. Writing `onAppear` in two places, forgetting to cancel
on `onDisappear`, letting the wait run while backgrounded — none of those are failures of
``ImpressionTracker``, and none of them show up in a test of it.

So `AnalyticsSwiftUI` keeps its view modifiers empty of judgement. They forward to
`ImpressionSession`, which owns the tracker, the wait, and the send. The sleep function is
injectable, so re-entrancy, early dismissal, returning to a screen, backgrounding, and scrolling
past can all be pinned in a unit test with no real time passing.

## Deduplication scopes

``DedupScope`` has three cases, and ``DedupingAnalytics`` enforces every one of them.

| Scope | Means | How |
|---|---|---|
| ``DedupScope/session`` | Once while the app is running | An in-memory set on the instance, guarded by a lock. A new instance starts empty |
| ``DedupScope/install`` | Once in the lifetime of the install | A boolean flag in `UserDefaults`, keyed by the event's `dedupKey`. Losing the defaults means counting once more, which is the safe direction |
| ``DedupScope/always`` | Every time | Passed straight through. For interactions, the number of times is the measurement |

## Per-exposure counting is not a scope

Counting a display once per exposure — again after leaving and returning — is the rule
``ImpressionTracker`` implements, and it is settled by *which mechanism fires the event*, not by a
field on the event. A `screen` or an `impression` is fired through `trackScreen` or
`trackImpression`, and those count once per exposure by construction.

It is deliberately not a ``DedupScope`` case, because the send path could not enforce one. Scopes
are keyed by ``AnalyticsEvent/dedupKey``, which ignores parameters: twenty rows of a list firing
the same impression event share a key, so a per-exposure window applied there would collapse
them into a single count. A scope that can only be honoured by the caller happening to pick the
right firing mechanism is a claim nothing backs, so it is the mechanism that carries the rule.

A suppressed send is dropped silently and is not counted anywhere. That is deliberate: the
alternative — recording the suppression — turns the log into something that has to be reconciled,
and the point of the scope is that the call site never has to think about it.

## The key a scope is remembered by

`session` and `install` remember an event by ``AnalyticsEvent/dedupKey``, which defaults to the
event's name and deliberately ignores parameters. "Responded to a notification prompt for the first
time" is once, not once per prompt stage. Override `dedupKey` on the conforming type only when you
genuinely want one occurrence per parameter value.

User properties are never deduplicated. A property is a statement about the current state, so
setting the same value twice changes nothing, and suppressing a repeat would leave a stale value in
place after a restore.
