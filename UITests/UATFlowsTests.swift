import XCTest

final class UATFlowsTests: XCTestCase {
    @MainActor func testComposerAndRefreshRecoveryUseFictionalTransport() {
        let app = fixture()
        XCTAssertTrue(app.staticTexts["uat.fixture"].waitForExistence(timeout:10))
        app.buttons["settings"].tap()
        app.buttons["Reload"].tap()
        XCTAssertTrue(app.staticTexts["You're offline. Connect and try again."].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["uat.fixture"].exists,"Failed refresh must retain content")
        app.buttons["tab-Messages"].tap()
        app.buttons.containing(.staticText,identifier:"UAT fixture").firstMatch.tap()
        let draft = app.textFields["message-draft"].exists ? app.textFields["message-draft"] : app.textViews["message-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        draft.tap(); draft.typeText("Hello from the fictional UAT test")
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = "Fictional native DM composer"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testUnconfirmedSendRequiresReconciliationBeforeAnotherSend() {
        let app = fixture(extra:["--uat-unconfirmed"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText,identifier:"UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
        let draft = app.textFields["message-draft"].exists ? app.textFields["message-draft"] : app.textViews["message-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:5)); draft.tap(); draft.typeText("Only one copy")
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        app.buttons["Check conversation"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].waitForNonExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled,"Confirmed send must clear the old draft")
    }
    @MainActor private func fixture(extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.terminate()
        app.launchArguments = ["--native","--uat-fixture"] + extra
        app.launch(); return app
    }
}
