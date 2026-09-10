import XCTest
import WebKit
@testable import Porch

@MainActor
final class DataAdapterTests: XCTestCase {
    func testFollowingContentIsFilteredBeforeRenderingAndPaginationIsExplicit() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        const image = {media_type:1,image_versions2:{candidates:[{url:'https://s.cdninstagram.com/photo.jpg',width:1080,height:1350}]}};
        const post = (id, overrides={}) => ({...image,id,user:{pk:1,username:'friend',friendship_status:{following:true}},taken_at:Number(id),caption:{text:'The word Sponsored in an ordinary caption'},...overrides});
        globalThis.pages = [
          {status:'ok',pagination_source:'following',more_available:true,next_max_id:'next page',feed_items:[
            {media_or_ad:post('1')}, {media_or_ad:post('1')},
            {media_or_ad:post('2',{ad_id:'advertisement'})},
            {media_or_ad:post('3',{product_type:'clips',media_type:2})},
            {media_or_ad:post('4',{user:{pk:2,username:'stranger',friendship_status:{following:false}}})},
            {media_or_ad:post('5',{user:{pk:3,username:'unknown'}})},
            {suggested_users:{users:[post('6')]}},
            {media_or_ad:post('7',{is_paid_partnership:true})},
            {media_or_ad:post('8',{media_type:8,carousel_media:[image,{...image,media_type:2,video_versions:[{url:'https://v.fbcdn.net/video.mp4'}]}]})},
            {media_or_ad:post('9',{image_versions2:{candidates:[{url:'https://s.cdninstagram.com.evil.example/photo.jpg'}]}})}
          ]},
          {status:'ok',pagination_source:'following',more_available:false,feed_items:[{media_or_ad:post('10')}]}
        ];
        """#)
        let feed = try await harness.request("feed")
        XCTAssertNil(feed.error)
        XCTAssertEqual(feed.posts.map(\.id), ["8", "1"])
        XCTAssertEqual(feed.posts.first?.media.count, 2)
        XCTAssertNotNil(feed.posts.first?.media.last?.videoURL)
        XCTAssertTrue(feed.stories.isEmpty && feed.threads.isEmpty)
        XCTAssertTrue(feed.hasMore)
        let firstPath = try await harness.script("return calls[0].path;") as? String
        XCTAssertTrue(firstPath?.contains("pagination_source=following") == true)
        XCTAssertFalse(firstPath?.contains("variant=") == true)
        let next = try await harness.request("moreFeed")
        XCTAssertEqual(next.posts.map(\.id), ["10"])
        XCTAssertFalse(next.hasMore)
        let nextPath = try await harness.script("return calls[1].path;") as? String
        XCTAssertTrue(nextPath?.contains("max_id=next%20page") == true)
        let exhausted = try await harness.request("moreFeed")
        XCTAssertEqual(exhausted.error, "unavailable")
        let observed1 = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(observed1, 2)
    }

    func testStoriesAndAcceptedInboxStaySeparateAndDetailsRequireListedIDs() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        const followed = {pk:11,username:'friend',friendship_status:{following:true}};
        globalThis.pages = [
          {tray:[{user:followed},{user:{pk:12,username:'stranger',friendship_status:{following:false}}},{user:{pk:13,username:'unknown'}},{user:followed,is_ad:true}]},
          {reels:{'11':{user:followed,items:[{id:'story',media_type:1,image_versions2:{candidates:[{url:'https://s.cdninstagram.com/story.jpg'}]}},{id:'ad',is_ad:true}]}}},
          {inbox:{threads:[{thread_id:'21',thread_title:'Friend',items:[{text:'Hello'}]},{thread_id:'22',pending:true}]}},
          {thread:{items:[{item_id:'b',item_type:'text',text:'Second'},{item_id:'a',item_type:'text',text:'First'}]}}
        ];
        """#)
        let notListed = try await harness.request("story", identifier:"11")
        XCTAssertEqual(notListed.error, "unavailable")
        let stories = try await harness.request("stories")
        XCTAssertEqual(stories.stories.map(\.id), ["11"])
        XCTAssertTrue(stories.posts.isEmpty && stories.threads.isEmpty)
        let story = try await harness.request("story", identifier:"11")
        XCTAssertEqual(story.posts.map(\.id), ["story"])
        let inbox = try await harness.request("inbox")
        XCTAssertEqual(inbox.threads.map(\.id), ["21"])
        XCTAssertTrue(inbox.posts.isEmpty && inbox.stories.isEmpty)
        let invalid = try await harness.request("thread", identifier:"../21")
        XCTAssertEqual(invalid.error, "unavailable")
        let thread = try await harness.request("thread", identifier:"21")
        XCTAssertEqual(thread.messages.map(\.text), ["First", "Second"])
        let observed2 = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(observed2, 4)
        let observed3 = try await harness.script("return calls.every(c => c.options.method === 'GET' && c.options.credentials === 'include' && c.options.redirect === 'error');") as? Bool
        XCTAssertEqual(observed3, true)
    }

    func testChangedSchemaAuthenticationAndRateLimitsDoNotMasqueradeAsEmptyContent() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        globalThis.pages = [
          {status:'ok',pagination_source:'recommended',feed_items:[]},
          {status:'ok',pagination_source:'following',feed_items:[],is_shell_response:true},
          {__http:429}, {__http:401}, {inbox:{}}, {status:'fail',message:'login_required'}
        ];
        """#)
        for (operation, expected) in [("feed","unsupported"),("feed","unsupported"),("stories","rateLimited"),("feed","signIn"),("inbox","unsupported"),("feed","signIn")] {
            let result = try await harness.request(operation)
            XCTAssertEqual(result.error, expected)
            XCTAssertTrue(result.posts.isEmpty)
        }
        let observed4 = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(observed4, 6, "No automatic request retries")
        let observed5 = try await harness.script("return document.scripts.length;") as? Int
        XCTAssertEqual(observed5, 0, "The document must not load Instagram application scripts")
    }

    func testNativeMediaRejectsForeignAndCredentialBearingURLs() {
        XCTAssertNotNil(InstagramPost.Media.mediaURL("https://s.cdninstagram.com/image.jpg"))
        XCTAssertNotNil(InstagramPost.Media.mediaURL("https://v.fbcdn.net/video.mp4"))
        for url in ["http://s.cdninstagram.com/x", "https://s.cdninstagram.com.evil.test/x", "https://name:secret@s.cdninstagram.com/x", "https://s.cdninstagram.com:8443/x", "file:///tmp/image"] {
            XCTAssertNil(InstagramPost.Media.mediaURL(url))
        }
    }
}

@MainActor
private final class AdapterHarness: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var ready: CheckedContinuation<Void, Error>?
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame:.zero,configuration:config)
        super.init()
        webView.navigationDelegate = self
    }
    func prepare() async throws {
        try await withCheckedThrowingContinuation { ready = $0
            webView.loadHTMLString("<!doctype html><html><body></body></html>",baseURL:URL(string:"https://www.instagram.com/"))
        }
        try await script(#"""
        globalThis.calls = [];
        globalThis.fetch = async (path,options) => {
          calls.push({path,options});
          const body = pages.shift();
          const status = body.__http || 200;
          return {status,ok:status === 200,json:async()=>body};
        };
        """#)
    }
    @discardableResult func script(_ text:String) async throws -> Any? {
        try await webView.callAsyncJavaScript(text,arguments:[:],in:nil,contentWorld:.defaultClient)
    }
    func request(_ operation:String,identifier:String = "") async throws -> InstagramDataResult {
        let path = try XCTUnwrap(Bundle.main.url(forResource:"instagram-data",withExtension:"js"))
        let source = try String(contentsOf:path,encoding:.utf8)
        let output = try await webView.callAsyncJavaScript(source,arguments:["operation":operation,"identifier":identifier],in:nil,contentWorld:.defaultClient)
        let text = try XCTUnwrap(output as? String)
        return try JSONDecoder().decode(InstagramDataResult.self,from:Data(text.utf8))
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { ready?.resume(); ready = nil }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { ready?.resume(throwing:error); ready = nil }
}
