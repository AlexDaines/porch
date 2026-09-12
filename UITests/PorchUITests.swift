import XCTest

final class PorchUITests: XCTestCase {
    @MainActor func testColorIntroductionAndSettingsPersistAcrossLaunches() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--appearance-fixture", "--reset-appearance"]
        app.launch()
        XCTAssertTrue(app.buttons["color-continue"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.buttons["color-sage"].isSelected)
        XCTAssertEqual(app.buttons["color-continue"].frame.midX, app.frame.midX, accuracy: 1)
        let colorCenter = (app.buttons["color-sage"].frame.minX + app.buttons["color-sand"].frame.maxX) / 2
        XCTAssertEqual(colorCenter, app.frame.midX, accuracy: 1)
        capture(app, "Color introduction")
        app.buttons["color-mist"].tap()
        XCTAssertTrue(app.buttons["color-mist"].isSelected)
        app.buttons["color-continue"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["connect"].frame.midX, app.frame.midX, accuracy: 1)
        app.buttons["sample"].tap()
        capture(app, "Mist sample feed")
        app.buttons["settings"].tap()
        app.buttons["settings-color"].tap()
        XCTAssertTrue(app.buttons["color-mist"].isSelected)
        app.buttons["color-lilac"].tap()
        XCTAssertTrue(app.buttons["color-lilac"].isSelected)
        capture(app, "Color settings")

        app.terminate()
        app.launchArguments = ["--appearance-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 10), "The introduction must only appear once")
        XCTAssertFalse(app.buttons["color-continue"].exists)
        app.buttons["sample"].tap()
        app.buttons["settings"].tap()
        app.buttons["settings-color"].tap()
        XCTAssertTrue(app.buttons["color-lilac"].isSelected, "Settings changes must survive restart")

        app.terminate()
        app.launchArguments = ["--appearance-fixture", "--reset-appearance", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["color-continue"].waitForExistence(timeout: 10))
        for name in ["sage", "sea", "mist", "lilac", "sand"] {
            XCTAssertTrue(app.buttons["color-\(name)"].isHittable)
        }
        if !app.buttons["color-continue"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["color-continue"].isHittable)
        capture(app, "Large text color introduction")
        app.buttons["color-continue"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 3), "Continuing with the default color must work")
    }

    @MainActor func testSampleNavigationAndFinish() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.terminate()
        // Explicitly pin the normal-size starting condition after the earlier
        // accessibility-size journey.
        app.launchArguments = ["--sample", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["SAMPLE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].exists)
        XCTAssertFalse(app.buttons["Maya's sample story"].exists)
        capture(app, "Sample feed")
        app.buttons["tab-Stories"].tap()
        XCTAssertTrue(app.buttons["Maya's sample story"].waitForExistence(timeout: 10), "The Stories destination must appear after one tab tap")
        XCTAssertTrue(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].waitForNonExistence(timeout: 10), "Feed media must leave the Stories screen")
        capture(app, "Sample stories")
        app.buttons["Maya's sample story"].tap()
        XCTAssertTrue(app.buttons["Next story"].waitForExistence(timeout: 3))
        app.buttons["Next story"].tap()
        XCTAssertTrue(app.staticTexts["Jules"].exists)
        capture(app, "Sample story viewer")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Ari's sample story"].exists)
        app.buttons["tab-Messages"].tap()
        XCTAssertTrue(app.staticTexts["Coffee on Sunday?"].exists)
        capture(app, "Sample messages")
        app.buttons.containing(.staticText, identifier: "Coffee on Sunday?").firstMatch.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
        capture(app, "Sample conversation")
        app.buttons["Close"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["settings-title"].waitForExistence(timeout: 3))
        capture(app, "Settings")
        app.buttons["clear-data"].tap()
        XCTAssertTrue(app.buttons["Clear website data"].waitForExistence(timeout: 3))
        capture(app, "Clear sign-in confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["clear-data"].exists, "Cancelling must retain the current session")
        app.buttons["Finish session"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 3))
        capture(app, "Welcome")

        app.terminate()
        app.launchArguments = ["--sample", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-Stories"].waitForExistence(timeout: 10))
        for tab in ["Feed", "Stories", "Messages"] {
            XCTAssertTrue(app.buttons["tab-\(tab)"].isHittable)
        }
        app.buttons["tab-Stories"].tap()
        XCTAssertTrue(app.buttons["Maya's sample story"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings"].isHittable)
        capture(app, "Large text stories")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // Let sheet/tab compositing finish before keeping a public sample screenshot.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
