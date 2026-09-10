import Foundation
import Testing
@testable import Porch

struct NavigationPolicyTests {
    @Test(arguments: [
        "https://www.instagram.com/?variant=following", "https://instagram.com/direct/inbox/",
        "https://www.instagram.com/stories/maya/123/", "https://www.instagram.com/accounts/login/",
        "https://www.instagram.com/challenge/", "https://www.instagram.com/p/abc/"
    ]) func intendedRoutesRemainAvailable(_ value: String) {
        #expect(NavigationPolicy.classify(URL(string: value)!) == .allow)
    }

    @Test(arguments: [
        "https://www.instagram.com/reels/", "https://www.instagram.com/reel/abc/",
        "https://www.instagram.com/explore/", "https://www.instagram.com/%72eels/",
        "https://www.instagram.com/%2572eels/", "https://www.instagram.com/user/reels/"
    ]) func discoveryRoutesStayClosed(_ value: String) {
        #expect(NavigationPolicy.classify(URL(string: value)!) == .blockedSurface)
    }

    @Test(arguments: [
        "http://www.instagram.com/", "javascript:alert(1)", "file:///tmp/test.html",
        "https://user:password@www.instagram.com/", "https://www.instagram.com:8443/",
        "https://www.instagram.com.evil.example/", "https://instagram.com@evil.example/"
    ]) func unsafeOriginsNeverEnterTheSession(_ value: String) {
        #expect(NavigationPolicy.classify(URL(string: value)!) != .allow)
    }

}
