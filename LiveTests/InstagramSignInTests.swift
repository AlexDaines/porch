import XCTest

// Opt-in, signed-out check. Never enters credentials or captures account content.
final class InstagramSignInTests: XCTestCase {
    @MainActor func testFreshLaunchReachesSignInAndCancelReturnsToWelcome() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--appearance-fixture", "--reset-appearance"]
        app.launch()
        XCTAssertTrue(app.buttons["color-continue"].waitForExistence(timeout: 10))
        app.buttons["color-continue"].tap()
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3))
        XCTAssertEqual(connect.label, "Sign in to Instagram", "Use a signed-out simulator for this test")
        connect.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 3), "Sign-in opens directly, without a feed request")
        XCTAssertFalse(app.buttons["tab-Feed"].exists)
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 30))
        capture("Signed-out Instagram form")
        XCTAssertTrue(app.staticTexts["Sign in above to open Porch."].exists)
        XCTAssertFalse(app.buttons["sign-in-continue"].exists, "The form must have one clear sign-in action")
        XCTAssertTrue(app.webViews.firstMatch.exists)
        app.buttons["Cancel sign-in"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 3))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertFalse(app.buttons["tab-Feed"].exists)
        capture("Welcome after cancelling sign-in")
        connect.tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 30), "A new attempt must mount a new functioning web view")
        app.buttons["Cancel sign-in"].tap()
    }
    @MainActor private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
