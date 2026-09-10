import XCTest
@testable import Porch

@MainActor
final class MediaPlaybackTests: XCTestCase {
    func testNativePlaybackAdvancesAndStopReleasesPlayer() async throws {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"playback",withExtension:"mp4"))
        let playback = MediaPlayback()
        defer { playback.stop() }
        XCTAssertNil(playback.player)
        playback.start(url)
        let deadline = Date().addingTimeInterval(12)
        while playback.elapsed < 0.75 && Date() < deadline {
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(playback.elapsed,0.75,"The native player must advance, not merely identify a playable asset")
        XCTAssertEqual(playback.state,.playing)
        playback.stop()
        XCTAssertNil(playback.player)
        XCTAssertEqual(playback.state,.idle)
    }
    func testInvalidAssetOffersFailureInsteadOfPermanentSpinner() async throws {
        let playback = MediaPlayback()
        defer { playback.stop() }
        playback.start(URL(fileURLWithPath:"/nonexistent/porch-fixture.mp4"))
        let deadline = Date().addingTimeInterval(5)
        while playback.state == .loading && Date() < deadline { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(playback.state,.failed)
        XCTAssertNil(playback.player)
    }
}
