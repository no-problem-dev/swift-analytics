import XCTest

/// SwiftUI が本当に信号を送るかを、実際に動かして確かめる。
///
/// ここに書くのは **`ImpressionSession` のテストでは書けないものだけ**（`Example/HAZARDS.md`）。
/// 数え方そのものはユニットで固定してあるので、ここで重ねて確かめない。
///
/// 読むのは画面上の 1 本の文字列（`probe.readout` = `screen=1 sheet=0 row=0 offscreen=0`）。
/// **絵ではなく数字を見る** ——「1 回のはずが 2 回」も「戻ったのに数え直していない」も、
/// スクリーンショットでは同じに見える。
final class ImpressionProbeTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: 道具

    private func launch(dwell: Double = 1.0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dwell", String(dwell)]
        app.launch()
        return app
    }

    /// 数字が期待どおりになるまで待つ。**滞在時間ぶんの猶予を必ず取る。**
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

    /// 数字が変わらないことを確かめる。**待たずに断じない** —— 遅れて出てくる発火を見逃す。
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

    // MARK: H4 押し戻ってから入り直す

    func test_画面に入ると1回だけ数える() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)
        // 留まっていても増えない
        expectStays(app, "screen", 1)
    }

    func test_押し戻ってから入り直すと数え直す() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)
        app.navigationBars.buttons.element(boundBy: 0).tap()   // 戻る
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 2)
    }

    // MARK: H5 滞在しきる前に離れる

    func test_滞在しきる前に戻ったら数えない() {
        // 遷移アニメーションを挟んでも操作が滞在時間より速く終わるよう、長めにする
        let app = launch(dwell: 8)
        app.buttons["probe.screen.push"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expectStays(app, "screen", 0, seconds: 4)
    }

    // MARK: H1 タブを離れて戻る

    func test_タブを離れて戻ると数え直す() {
        let app = launch()
        app.buttons["probe.screen.push"].tap()
        expect(app, "screen", 1)

        app.tabBars.buttons.element(boundBy: 1).tap()   // 一覧へ
        app.tabBars.buttons.element(boundBy: 0).tap()   // 画面へ戻る

        // **ここが落ちたら H1 を踏んでいる**（タブを離れても onDisappear が来ず、
        // 露出の一区切りが終わらないので、戻ってきても数え直さない）
        expect(app, "screen", 2)
    }

    // MARK: H2 シートを出し直す

    func test_シートを出し直すと数え直す() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 2).tap()

        app.buttons["probe.sheet.present"].tap()
        expect(app, "sheet", 1)
        app.buttons["probe.sheet.dismiss"].tap()

        app.buttons["probe.sheet.present"].tap()
        expect(app, "sheet", 2)
    }

    // MARK: H3 画面外の要素

    func test_画面外の要素は数えない() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 1).tap()

        // **ここが 0 でなかったら H3 を踏んでいる**（遅延生成の行にも可視の通知が来ていて、
        // 「見ていない露出」が数字に混ざる）
        expectStays(app, "offscreen", 0, seconds: 3)
        expectStays(app, "row", 0)
    }

    // MARK: H6 スクロールして見える／通り過ぎる

    func test_スクロールして留まったら数える() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 1).tap()

        // **要素が掴めたか**ではなく**数字が変わったか**で進める。
        // `isHittable` は、スクロールの中の要素については当てにならなかった
        // （25 回送っても false のままで、実際には画面に出ていた）。
        // どのみち確かめたいのは数字なので、そちらを直接見る。
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
