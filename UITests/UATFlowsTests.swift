import XCTest

final class UATFlowsTests: XCTestCase {
    @MainActor func testFeedChoiceLoadsOnlyOnSelectionAndRetainsOverflow() {
        let app = fixture(extra: ["--uat-feed-choice"])
        let more = app.buttons["feed-more-posts"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["feed-loaded-count"].label, "1 post loaded")
        XCTAssertGreaterThanOrEqual(more.frame.height, 44)
        snapshot("Feed choice closed")
        more.tap()
        for amount in [5, 10, 20] { XCTAssertTrue(app.buttons["Up to \(amount) posts"].waitForExistence(timeout: 5)) }
        snapshot("Feed choice open")
        app.buttons["tab-Feed"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Up to 5 posts"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["feed-loaded-count"].label, "1 post loaded", "Opening and dismissing must not load posts")
        more.tap(); app.buttons["Up to 5 posts"].tap()
        reachFeedBoundary(app, target: more, count: 6)
        XCTAssertEqual(app.staticTexts["feed-loaded-count"].label, "6 posts loaded", "Server overflow must stay pending")
        more.tap(); app.buttons["Up to 10 posts"].tap()
        let end = app.staticTexts["feed-end"]
        reachFeedBoundary(app, target: end, count: 11)
        XCTAssertEqual(app.staticTexts["feed-loaded-count"].label, "11 posts loaded", "Reveal the pending three and short final two without another page")
        XCTAssertEqual(end.label, "No more posts")
        XCTAssertFalse(more.exists)
    }
    @MainActor func testFeedChoiceAtLargestTextSizeKeepsAllAmountsReachable() {
        let app = fixture(extra: ["--uat-feed-choice", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let more = app.buttons["feed-more-posts"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        reachFeedBoundary(app, target: more, count: 1)
        XCTAssertGreaterThanOrEqual(more.frame.height, 44)
        snapshot("Large text feed choice closed")
        more.tap()
        for amount in [5, 10, 20] {
            let option = app.buttons["Up to \(amount) posts"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            XCTAssertTrue(option.isHittable)
            XCTAssertGreaterThanOrEqual(option.frame.height, 44)
        }
        snapshot("Large text feed choice open")
        app.buttons["Up to 5 posts"].tap()
        reachFeedBoundary(app, target: more, count: 6)
        XCTAssertEqual(app.staticTexts["feed-loaded-count"].label, "6 posts loaded")
    }
    @MainActor private func reachFeedBoundary(_ app: XCUIApplication, target: XCUIElement, count: Int) {
        // Move to the deliberate boundary; scrolling itself must never fetch.
        for _ in 0..<20 {
            let loaded = app.staticTexts["feed-loaded-count"]
            let expected = "\(count) \(count == 1 ? "post" : "posts") loaded"
            if target.exists && target.isHittable && loaded.exists && loaded.label == expected && !app.progressIndicators.firstMatch.exists { return }
            app.scrollViews["native-feed"].swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, "The feed boundary must remain reachable")
    }
    @MainActor private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testReconciliationPreservesEditsMadeWhileChecking() {
        let app = fixture(extra: ["--uat-unconfirmed", "--uat-delayed-reconcile"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText, identifier: "UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let draft = app.descendants(matching: .any).matching(identifier: "message-draft").firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        enterDraft("Submitted snapshot", in: draft, app: app)
        app.buttons["send-message"].tap()
        let check = app.buttons["Check conversation"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        XCTAssertFalse(check.isEnabled)
        app.typeText(" plus a newer draft")
        XCTAssertEqual(draft.value as? String, "Submitted snapshot plus a newer draft")
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You: Submitted snapshot"].exists)
        XCTAssertEqual(draft.value as? String, "Submitted snapshot plus a newer draft")
        XCTAssertFalse(check.exists)
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        app.buttons["Close conversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Submitted snapshot plus a newer draft")
    }

    @MainActor func testReceiptPreservesEditsMadeWhileSending() {
        let app = fixture(extra: ["--uat-delayed-send"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText, identifier: "UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let draft = app.descendants(matching: .any).matching(identifier: "message-draft").firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        enterDraft("First message", in: draft, app: app)
        app.buttons["send-message"].tap()
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        app.typeText(" plus an edit")
        XCTAssertEqual(draft.value as? String, "First message plus an edit")
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You: First message"].exists)
        XCTAssertEqual(draft.value as? String, "First message plus an edit", "The receipt must not erase a newer edit")
        app.buttons["Close conversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "First message plus an edit", "The newer draft must survive reopening")
    }

    @MainActor func testComposerPaddingFocusesAndAcceptsTypingAfterOneTap() {
        let app = fixture(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText, identifier: "UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        var expected = ""
        for corner in [CGVector(dx: 0, dy: 0), CGVector(dx: 1, dy: 0),
                       CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 1)] {
            row.tap()
            let draft = app.descendants(matching: .any).matching(identifier: "message-draft").firstMatch
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            let surface = app.otherElements["message-entry-surface"]
            XCTAssertTrue(surface.exists)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            let inset = CGVector(dx: corner.dx == 0 ? 2 : -2, dy: corner.dy == 0 ? 2 : -2)
            let tap = surface.coordinate(withNormalizedOffset: corner).withOffset(inset)
            XCTAssertFalse(draft.frame.contains(tap.screenPoint), "Exercise the visible padding, outside the native field's bounds")
            tap.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "One tap inside the visible corner must focus the composer")
            // Type through the keyboard; do not tap/focus the field again or let
            // a field-targeted typing helper repair a missed first tap.
            app.typeText("x")
            expected += "x"
            XCTAssertEqual(draft.value as? String, expected)
            XCTAssertTrue(app.buttons["send-message"].isEnabled)
            XCTAssertFalse(app.staticTexts["message-sent"].exists, "Focusing must never send")
            app.buttons["Close conversation"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
    }

    @MainActor func testMultilineComposerPaddingAtLargestTextSize() {
        let app = fixture(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["tab-Messages"].tap()
        let row = app.buttons.containing(.staticText, identifier: "UAT fixture").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let draft = app.descendants(matching: .any).matching(identifier: "message-draft").firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.label, "Message", "The composer remains a named native text input")
        let surface = app.otherElements["message-entry-surface"]
        surface.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let text = "One line\nAnother line\nRoom to write."
        app.typeText(text)
        XCTAssertEqual(draft.value as? String, text)
        XCTAssertTrue(app.buttons["send-message"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Large text multiline composer"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Close conversation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let corner = surface.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        XCTAssertFalse(draft.frame.contains(corner.screenPoint))
        corner.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("!")
        let edited = draft.value as? String ?? ""
        XCTAssertEqual(edited.count, text.count + 1)
        XCTAssertEqual(edited.replacingOccurrences(of: "!", with: ""), text)
        XCTAssertFalse(app.staticTexts["message-sent"].exists)
    }

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
        XCTAssertTrue(app.staticTexts["message-sent"].waitForExistence(timeout:5), "Reconciliation must label the matching outgoing message")
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
        let retainedFailure = app.staticTexts["diagnostics-last-failure"].label
        XCTAssertTrue(retainedFailure.contains("actionBlocked"),"Observed diagnostic summary: \(retainedFailure)")
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
        app.typeText(text)
        let firstValue = draft.value as? String
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: draft)
        let result = XCTWaiter.wait(for: [complete], timeout: 5)
        // Observe the result of this one input; do not repair it by typing or
        // focusing again. Slow accessibility updates must settle before Send.
        XCTAssertEqual(result, .completed, "The fixture draft must be entered before sending; first: \(String(describing: firstValue)), settled: \(String(describing: draft.value))")
        if firstValue != text, result == .completed {
            print("Composer accessibility value settled after typing: initial length \(firstValue?.count ?? 0), expected length \(text.count)")
        }
    }
    @MainActor private func fixture(extra:[String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.terminate()
        app.launchArguments = ["--native","--uat-fixture"] + extra
        if !extra.contains("-UIPreferredContentSizeCategoryName") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        app.launch(); return app
    }
}
