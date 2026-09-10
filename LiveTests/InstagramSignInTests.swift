import XCTest

// Opt-in, signed-out check. Never enters credentials or captures account content.
final class InstagramSignInTests: XCTestCase {
    @MainActor func testInstagramSignInPageIsReachable() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--sign-in"]
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 30),
                      "Requires a signed-out simulator; an existing session is not sign-in-page evidence.")
    }
}
