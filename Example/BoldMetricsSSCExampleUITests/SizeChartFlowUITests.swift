import XCTest

/// Drives the example against the local embed dev server (http://localhost:1337).
/// Needs the embed page served locally (see README). Set SSC_SHOTS_DIR
/// (TEST_RUNNER_SSC_SHOTS_DIR on the xcodebuild command line) to save screenshots and
/// the accessibility tree to disk.
final class SizeChartFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func launch(_ args: [String] = []) {
        app.launchArguments = args
        app.launch()
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SSC_SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            try? app.debugDescription.write(
                to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        }
    }

    func type(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 15), field.description)
        field.tap()
        field.typeText(text)
    }

    func logLines() -> [String] {
        app.staticTexts.matching(identifier: "eventLog").allElementsBoundByIndex.map(\.label)
    }

    func waitForLog(_ text: String, timeout: TimeInterval = 20) -> Bool {
        let predicate = NSPredicate(format: "identifier == 'eventLog' AND label BEGINSWITH %@", text)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Open → form → recommendation → add to cart → close, through the SwiftUI wrapper.
    func testRecommendationAndAddToCart() {
        launch()
        runFlow(expectSizeId: "M", variant: "mens-nano-vest-04")
    }

    /// UIKit controller, product delivered through init=bridge, women's product, closed with the page's X.
    func testUIKitBridgeInitAndPageClose() {
        launch(["-useUIKit", "YES", "-useBridgeInit", "YES", "-productIndex", "1"])
        app.buttons["findMySize"].tap()
        XCTAssertTrue(waitForLog("bmi_ssc_loaded"), logLines().joined(separator: "\n"))
        XCTAssertTrue(waitForLog("bmi_embed_boot"))
        let close = app.webViews.firstMatch.buttons["CLOSE"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(waitForLog("onClose"))
        XCTAssertTrue(app.buttons["findMySize"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists, "sheet should be dismissed")
        XCTAssertEqual(logLines().filter { $0 == "onClose" }.count, 1)
        shot("uikit-page-close")
        print("EVENT LOG:\n" + logLines().reversed().joined(separator: "\n"))
    }

    func runFlow(expectSizeId: String?, variant: String?, answers: [String] = ["5", "10", "180", "33", "32"]) {
        app.buttons["findMySize"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        // A returning shopper (answers saved in the web view's persistent store) skips the form.
        let feet = web.textFields["enter Height in feet"]
        let cta = web.buttons["Select Size"]
        _ = feet.waitForExistence(timeout: 10) || cta.waitForExistence(timeout: 10)
        if feet.exists {
            type(feet, answers[0])
            type(web.textFields["enter Height in inches"], answers[1])
            type(web.textFields["Weight"], answers[2])
            type(web.textFields["Age"], answers[3])
            if answers.count > 4 { type(web.textFields["Pant Waist"], answers[4]) }
            shot("flow-1-form-\(name)")
            if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
            sleep(1)
            web.buttons["FIND MY SIZE"].tap()
        }
        sleep(6)
        shot("flow-2-result-\(name)")
        // bmi's result CTA (the widget's add-to-cart) is labelled "Select Size".
        let addToCart = web.buttons["Select Size"]
        if addToCart.waitForExistence(timeout: 15) {
            if !addToCart.isHittable { web.swipeUp() }
            addToCart.tap()
        }
        sleep(3)
        shot("flow-3-after-cart-\(name)")
        XCTAssertTrue(waitForLog("bmi_add_to_cart"), logLines().joined(separator: "\n"))
        XCTAssertTrue(waitForLog("onClose"))
        XCTAssertEqual(app.otherElements["cartBadge"].value as? String, "1")
        if let expectSizeId { XCTAssertTrue(waitForLog("bmi_recommendation_sent sizeId=\(expectSizeId)")) }
        if let variant { XCTAssertTrue(waitForLog("bmi_selected_item variant=\(variant)")) }
        print("EVENT LOG:\n" + logLines().reversed().joined(separator: "\n"))
    }

    /// Swipe-dismiss → exactly one onClose, page closed through BoldMetricsEmbed.close().
    func testSwipeDismissReportsOneClose() {
        launch()
        app.buttons["findMySize"].tap()
        XCTAssertTrue(waitForLog("bmi_ssc_loaded"))
        let grabber = app.buttons["Sheet Grabber"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grabber.press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
        XCTAssertTrue(waitForLog("onClose"))
        sleep(2)
        shot("swipe-dismiss")
        let closes = logLines().filter { $0 == "onClose" }.count
        XCTAssertEqual(closes, 1, logLines().joined(separator: "\n"))
        print("EVENT LOG:\n" + logLines().reversed().joined(separator: "\n"))
    }

    func testExplore() {
        launch()
        app.buttons["findMySize"].tap()
        sleep(8)
        shot("explore-open")
    }
}
