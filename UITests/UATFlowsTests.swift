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
        enterDraft("Hello from the fictional UAT test",in:draft,app:app)
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
        XCTAssertTrue(draft.waitForExistence(timeout:5))
        enterDraft("Only one copy",in:draft,app:app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        app.buttons["I checked"].tap()
        XCTAssertTrue(app.buttons["Allow another message"].waitForExistence(timeout:5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].exists)
        XCTAssertFalse(app.buttons["send-message"].isEnabled,"Cancelling must keep the unresolved send blocked")
        XCTAssertEqual(draft.value as? String,"Only one copy","Cancelling must preserve the draft")
        app.buttons["Check conversation"].tap()
        XCTAssertTrue(app.buttons["Check conversation"].waitForNonExistence(timeout:5))
        XCTAssertFalse(app.buttons["send-message"].isEnabled,"Confirmed send must clear the old draft")
    }
    @MainActor func testBlockedSendKeepsDraftAndNeverShowsSent() {
        let app = fixture(extra:["--uat-blocked"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText,identifier:"UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
        let draft = app.textFields["message-draft"].exists ? app.textFields["message-draft"] : app.textViews["message-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:5))
        enterDraft("Keep this draft",in:draft,app:app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["Instagram restricted this action. Open Instagram to review it."].waitForExistence(timeout:5))
        XCTAssertEqual(draft.value as? String,"Keep this draft")
        XCTAssertFalse(app.staticTexts["message-sent"].exists)
        XCTAssertFalse(app.buttons["Check conversation"].exists)
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = "Fictional blocked DM preserves draft"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testDiagnosticsKeepsFailureAfterRestartAndOpensFileShare() {
        let app = fixture(extra:["--uat-blocked"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText,identifier:"UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5)); row.tap()
        let draft = app.textFields["message-draft"].exists ? app.textFields["message-draft"] : app.textViews["message-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout:5))
        enterDraft("PRIVATE UAT CANARY",in:draft,app:app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts["Instagram restricted this action. Open Instagram to review it."].waitForExistence(timeout:5))
        app.terminate(); app.launch()
        app.buttons["settings"].tap()
        app.buttons["settings-diagnostics"].tap()
        XCTAssertTrue(app.staticTexts["diagnostics-last-failure"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["diagnostics-last-failure"].label.contains("actionBlocked"))
        XCTAssertTrue(app.staticTexts["diagnostics-count"].exists)
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = "Fictional durable diagnostics"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["diagnostics-share"].tap()
        XCTAssertTrue(app.collectionViews["activityCollectionView"].waitForExistence(timeout:10), "The generated file must open in the system share sheet")
        let filename = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ OR label == %@","Porch-diagnostics","Porch-diagnostics.json")).firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout:10),"The share sheet must contain the generated diagnostic file")
    }
    @MainActor private func enterDraft(_ text:String,in draft:XCUIElement,app:XCUIApplication) {
        draft.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:10),"The composer keyboard must be ready before typing")
        // Keyboard presentation moves this bottom-anchored field; focus its settled position.
        draft.tap()
        draft.typeText(text)
        XCTAssertEqual(draft.value as? String,text,"The fixture draft must be entered before sending")
    }
    @MainActor private func fixture(extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.terminate()
        app.launchArguments = ["--native","--uat-fixture"] + extra
        app.launch(); return app
    }
}
