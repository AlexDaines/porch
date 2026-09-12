import XCTest

// Staff regression checks use selectors. These tests are never blind participants
// and their actions are never used as the study reference action count.
final class BlindUIJourneyTests: XCTestCase {
    @MainActor func testNormalNativeJourneyAndFreshRunReset() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["maya"].waitForExistence(timeout: 10))
        capture("Blind UI home")
        app.buttons["tab-Messages"].tap()
        let mom = app.buttons.containing(.staticText, identifier: "Mom").firstMatch
        XCTAssertTrue(mom.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Maya"].exists)
        XCTAssertTrue(app.staticTexts["Aunt Linda"].exists)
        capture("Blind UI inbox with distractors")
        mom.tap()
        enter("Thinking of you. How is your day?", app: app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        capture("Blind UI accepted message")
        app.terminate()
        let fresh = launch()
        XCTAssertTrue(fresh.staticTexts["maya"].waitForExistence(timeout: 10))
        fresh.buttons["tab-Messages"].tap()
        fresh.buttons.containing(.staticText, identifier: "Mom").firstMatch.tap()
        XCTAssertFalse(fresh.staticTexts["message-sent"].exists)
        XCTAssertFalse(fresh.staticTexts["You: Thinking of you. How is your day?"].exists)
    }
    @MainActor func testUnconfirmedWriteCannotAutomaticallyResend() {
        let app = launch(control: "accepted-unconfirmed")
        app.buttons["tab-Messages"].tap()
        app.buttons.containing(.staticText, identifier: "Mom").firstMatch.tap()
        enter("Thinking of you. How is your day?", app: app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        capture("Blind UI uncertain acknowledgement")
        app.buttons["Check conversation"].tap()
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
    }
    @MainActor private func launch(control: String = "accepted") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--blind-ui-fixture", "--blind-ui-run-id", UUID().uuidString.lowercased(), "--blind-ui-control", control]
        app.launch()
        return app
    }
    @MainActor private func enter(_ text: String, app: XCUIApplication) {
        let draft = app.textFields["message-draft"].exists ? app.textFields["message-draft"] : app.textViews["message-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        draft.tap(); draft.typeText(text)
        XCTAssertEqual(draft.value as? String, text)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
