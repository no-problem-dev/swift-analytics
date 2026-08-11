import XCTest

/// Checks, by running it for real, whether SwiftUI actually sends the signals.
///
/// Only what **cannot be written as an `ImpressionSession` test** goes here (see
/// `Example/HAZARDS.md`). The counting itself is pinned by the unit tests, so it is not checked
/// again here.
///
/// What is read is one string on screen (`probe.readout` = `screen=1 sheet=0 row=0 offscreen=0`).
/// **Numbers, not pictures** — "twice where once was meant" and "came back but never counted
/// again" look the same in a screenshot.
final class ImpressionProbeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Tools

    private func launch(dwell: Double = 1.0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dwell", String(dwell)]
        app.launch()
        return app
    }

    /// Waits until the number reaches what is expected. **Always leaves room for the dwell.**
    private func expect(
        _ app: XCUIApplication,
        _ name: String,
        _ value: Int,
        timeout: TimeInterval = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let readout = app.staticTexts["probe.readout"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "\(name)=\(value)")
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: readout)
        let result = XCTWaiter().wait(for: [matched], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "\(name)=\(value) にならなかった（いま \(readout.label)）",
            file: file, line: line
        )
    }

    /// Checks that the number does not change. **Never concludes without waiting** — a firing that
    /// arrives late would be missed.
    private func expectStays(
        _ app: XCUIApplication,
        _ name: String,
        _ value: Int,
        seconds: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        Thread.sleep(forTimeInterval: seconds)
        let label = app.staticTexts["probe.readout"].label
        XCTAssertTrue(
            label.contains("\(name)=\(value)"),
            "\(name)=\(value) のはずが \(label)",
            file: file, line: line
        )
    }

    // MARK: H4 popping back and going in again

    func test_画面に入ると1回だけ数える() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)
        // Staying on it does not raise the number
        expectStays(app, "screen", 1)
    }

    func test_押し戻ってから入り直すと数え直す() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 2)
    }

    // MARK: H5 leaving before the dwell is up

    func test_滞在しきる前に戻ったら数えない() {
        // Made long, so the interaction finishes inside the dwell even with a transition animation
        let app = launch(dwell: 8)
        app.buttons["probe.screen.push"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expectStays(app, "screen", 0, seconds: 4)
    }

    // MARK: H1 leaving a tab and coming back

    func test_タブを離れて戻ると数え直す() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)

        app.tabBars.buttons.element(boundBy: 1).tap()   // to the list
        app.tabBars.buttons.element(boundBy: 0).tap()   // back to the screen

        // **A failure here means hazard H1 has been hit** (leaving the tab brings no onDisappear,
        // so the exposure never ends and coming back does not count again)
        expect(app, "screen", 2)
    }

    // MARK: H2 presenting a sheet again

    func test_シートを出し直すと数え直す() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 2).tap()

        app.buttons["probe.sheet.present"].tap()
        expect(app, "sheet", 1)
        app.buttons["probe.sheet.dismiss"].tap()

        app.buttons["probe.sheet.present"].tap()
        expect(app, "sheet", 2)
    }

    // MARK: H3 an element that is off screen

    func test_画面外の要素は数えない() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 1).tap()

        // **Anything but 0 here means hazard H3 has been hit** (visibility notifications are
        // arriving for lazily built rows, mixing exposures nobody saw into the numbers)
        expectStays(app, "offscreen", 0, seconds: 3)
        expectStays(app, "row", 0)
    }

    // MARK: H6 scrolling into view, and scrolling past

    func test_スクロールして留まったら数える() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 1).tap()

        // Driven by **whether the number moved**, not by **whether the element could be grabbed**.
        // `isHittable` turned out to be unreliable for an element inside a scroll view (still
        // false after 25 swipes, while it was plainly on screen). The number is what is being
        // checked anyway, so look at that directly.
        let readout = app.staticTexts["probe.readout"]
        let list = app.scrollViews.firstMatch
        var attempts = 0
        while !readout.label.contains("row=1"), attempts < 15 {
            list.swipeUp()
            attempts += 1
        }

        expect(app, "row", 1)
    }
}
