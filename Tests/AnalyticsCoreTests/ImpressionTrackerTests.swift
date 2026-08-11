import Testing
@testable import AnalyticsCore

/// Pins the definition of "was seen".
///
/// **No simulator and no waiting in real time.** Nothing here holds a clock, so whether the
/// counting is right can be checked as pure state transitions.
@Suite("見えたの定義")
struct ImpressionTrackerTests {

    @Test("半分以上が見えたら、待ちを始める")
    func startsDwellWhenVisibleEnough() {
        var tracker = ImpressionTracker()
        #expect(tracker.visibility(0.5) == .startDwell(1.0))
    }

    @Test("半分に満たなければ、待たない")
    func doesNotStartWhenBarelyVisible() {
        var tracker = ImpressionTracker()
        #expect(tracker.visibility(0.49) == .cancelDwell)
    }

    @Test("待っている間に消えたら数えない")
    func doesNotCountWhenHiddenBeforeDwellCompletes() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        #expect(tracker.visibility(0) == .cancelDwell)
        #expect(tracker.dwellCompleted() == false)
        #expect(tracker.hasFired == false)
    }

    @Test("見え続けたら 1 回だけ数える")
    func countsOnceWhenVisibleLongEnough() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        #expect(tracker.dwellCompleted() == true)
        // Never counted twice within one exposure
        #expect(tracker.dwellCompleted() == false)
    }

    @Test("数えたあとに見え方が揺れても、待ちを始め直さない")
    func doesNotRestartAfterFiring() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        _ = tracker.dwellCompleted()
        #expect(tracker.visibility(1) == .none)
    }

    @Test("画面から外れて戻ってきたら、また数える")
    func countsAgainInANewEpisode() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        #expect(tracker.dwellCompleted() == true)

        tracker.endEpisode()
        #expect(tracker.hasFired == false)
        #expect(tracker.visibility(1) == .startDwell(1.0))
        #expect(tracker.dwellCompleted() == true)
    }

    @Test("背面に落ちている間は数えない")
    func doesNotCountInBackground() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        #expect(tracker.foreground(false) == .cancelDwell)
        #expect(tracker.dwellCompleted() == false)
    }

    @Test("前面に戻ったら数え直す")
    func resumesWhenForegrounded() {
        var tracker = ImpressionTracker()
        _ = tracker.visibility(1)
        _ = tracker.foreground(false)
        #expect(tracker.foreground(true) == .startDwell(1.0))
        #expect(tracker.dwellCompleted() == true)
    }

    @Test("見えていない状態で満了しても数えない")
    func neverCountsWithoutVisibility() {
        var tracker = ImpressionTracker()
        #expect(tracker.dwellCompleted() == false)
    }

    @Test("しきい値と滞在時間は差し替えられる")
    func honoursCustomThresholdAndDwell() {
        var tracker = ImpressionTracker(threshold: 0.9, dwell: 2)
        #expect(tracker.visibility(0.8) == .cancelDwell)
        #expect(tracker.visibility(0.9) == .startDwell(2))
    }
}
