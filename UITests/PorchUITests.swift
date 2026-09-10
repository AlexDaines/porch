import XCTest

final class PorchUITests: XCTestCase {
    @MainActor func testSampleNavigationAndFinish() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.terminate()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.staticTexts["SAMPLE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].exists)
        XCTAssertFalse(app.buttons["Maya's sample story"].exists)
        capture(app, "Sample feed")
        app.buttons["tab-Stories"].tap()
        XCTAssertFalse(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].exists)
        capture(app, "Sample stories")
        app.buttons["Maya's sample story"].tap()
        XCTAssertTrue(app.buttons["Next story"].waitForExistence(timeout: 3))
        app.buttons["Next story"].tap()
        XCTAssertTrue(app.staticTexts["Jules"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Ari's sample story"].exists)
        app.buttons["tab-Messages"].tap()
        XCTAssertTrue(app.staticTexts["Coffee on Sunday?"].exists)
        capture(app, "Sample messages")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture(app, "Settings")
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 3))
        capture(app, "Welcome")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // Let sheet/tab compositing finish before keeping a public sample screenshot.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
