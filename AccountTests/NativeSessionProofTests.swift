import XCTest
import SwiftUI
import AVFoundation
@testable import Porch

final class NativeSessionProofTests: XCTestCase {
    @MainActor func testSavedSessionIsDiscoveredBeforeAnyContentRequest() async throws {
        let browser = InstagramBrowser()
        let saved = await browser.hasSavedSession()
        XCTAssertTrue(saved, "Discover the existing sign-in without opening Instagram or loading content")
        browser.suspend()
        let transport = WebKitInstagramTransport()
        defer { transport.close() }
        let result = try await transport.execute("session")
        XCTAssertNil(result.error, "The existing session must pass a real authenticated request")
        XCTAssertTrue(result.threads.isEmpty && result.messages.isEmpty)
    }

    @MainActor func testNativeFeedFromExistingSession() async throws {
        let client = InstagramDataClient()
        defer { client.close() }
        let result = try await client.request("feed")
        print("PORCH_NATIVE_RESULT posts=\(result.posts.count) error=\(result.error ?? "none")")
        XCTAssertNil(result.error)
        XCTAssertFalse(result.posts.isEmpty, "A real post is required for this proof.")
        guard !result.posts.isEmpty else { return }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene:scene)
        window.rootViewController = UIHostingController(rootView:NativeFeed(posts:result.posts).preferredColorScheme(.dark))
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for:.seconds(4))
        let renderer = UIGraphicsImageRenderer(bounds:window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
        let attachment = XCTAttachment(image:image)
        attachment.name = "Private native feed proof"
        attachment.lifetime = .keepAlways
        add(attachment)

        let stories = try await client.request("stories")
        print("PORCH_STORIES count=\(stories.stories.count) error=\(stories.error ?? "none")")
        XCTAssertNil(stories.error)
        XCTAssertTrue(stories.posts.isEmpty, "Stories must never bring a feed with them.")
        if let person = stories.stories.first {
            let story = try await client.request("story", identifier: person.id)
            print("PORCH_STORY_MEDIA count=\(story.posts.count) error=\(story.error ?? "none")")
            XCTAssertNil(story.error)
            XCTAssertFalse(story.posts.isEmpty, "An active story is required for this proof.")
            window.rootViewController = UIHostingController(rootView:NativeFeed(posts:story.posts).preferredColorScheme(.dark))
            try await Task.sleep(for:.seconds(3))
            let storyImage = renderer.image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
            let storyAttachment = XCTAttachment(image:storyImage)
            storyAttachment.name = "Private native story media proof"
            storyAttachment.lifetime = .keepAlways
            add(storyAttachment)
            if let url = story.posts.flatMap(\.media).compactMap(\.videoURL).first {
                let asset = AVURLAsset(url:url)
                let playable = try await asset.load(.isPlayable)
                XCTAssertTrue(playable, "Instagram's video URL must load as a native playable asset")
                let playback = MediaPlayback()
                playback.start(url,muted:true)
                let deadline = Date().addingTimeInterval(15)
                while playback.elapsed < 0.75 && Date() < deadline { try await Task.sleep(for:.milliseconds(100)) }
                let advanced = playback.elapsed >= 0.75
                playback.stop()
                XCTAssertTrue(advanced,"The real Instagram video must advance through native playback")
                print("PORCH_VIDEO assetPlayable=\(playable) playbackAdvanced=\(advanced)")
            }
        }
        let inbox = try await client.request("inbox")
        print("PORCH_INBOX count=\(inbox.threads.count) error=\(inbox.error ?? "none")")
        XCTAssertNil(inbox.error)
        XCTAssertTrue(inbox.posts.isEmpty && inbox.stories.isEmpty)
    }
}
