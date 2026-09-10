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
        capture(app, "Color introduction")
        app.buttons["color-mist"].tap()
        XCTAssertTrue(app.buttons["color-mist"].isSelected)
        app.buttons["color-continue"].tap()
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 3))
        app.buttons["sample"].tap()
        capture(app, "Mist sample feed")
        app.buttons["settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Color,")).firstMatch.tap()
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
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Color,")).firstMatch.tap()
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

        app.terminate()
        app.launchArguments = ["--sample", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-Stories"].waitForExistence(timeout: 10))
        for tab in ["Feed", "Stories", "Messages"] {
            XCTAssertTrue(app.buttons["tab-\(tab)"].isHittable)
        }
        app.buttons["tab-Stories"].tap()
        XCTAssertTrue(app.buttons["Maya's sample story"].exists)
        XCTAssertFalse(app.images["Sample landscape: a cabin and mountains reflected in a still lake"].exists)
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
