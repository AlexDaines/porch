import XCTest

// Explicit opt-in. Uses the existing sign-in; never follows, likes, sends, or posts.
final class NativeReadingTests: XCTestCase {
    @MainActor func testFeedStoriesAndInboxUseSeparateNativeViews() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--native"]
        app.launch()
        XCTAssertTrue(app.otherElements["native-post"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertFalse(app.scrollViews["native-stories"].exists)
        capture(app,"Private integrated native feed")
        app.buttons["tab-Stories"].tap()
        XCTAssertTrue(app.scrollViews["native-stories"].waitForExistence(timeout: 20))
        let story = app.buttons.matching(NSPredicate(format:"label ENDSWITH %@", "'s story")).firstMatch
        XCTAssertTrue(story.waitForExistence(timeout:20), "Needs a followed account with an active story")
        XCTAssertFalse(app.otherElements["native-post"].exists)
        capture(app,"Private separate stories")
        story.tap()
        XCTAssertTrue(app.images["native-post-image"].waitForExistence(timeout:20))
        XCTAssertEqual(app.webViews.count, 0)
        capture(app,"Private native story viewer")
        app.buttons["Close story"].firstMatch.tap()
        app.buttons["tab-Messages"].tap()
        XCTAssertTrue(app.scrollViews["native-inbox"].waitForExistence(timeout:20))
        XCTAssertTrue(app.activityIndicators.firstMatch.waitForNonExistence(timeout:20))
        XCTAssertFalse(app.scrollViews["native-stories"].exists)
        XCTAssertFalse(app.otherElements["native-post"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        capture(app,"Private accepted inbox")
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        Thread.sleep(forTimeInterval:1)
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
