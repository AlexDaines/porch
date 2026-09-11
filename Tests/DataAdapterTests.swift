import XCTest
import WebKit
@testable import Porch

@MainActor
final class DataAdapterTests: XCTestCase {
    func testSessionRequiresAuthenticatedInboxWithoutReturningMessages() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        let hint = try await harness.request("sessionHint")
        XCTAssertEqual(hint.diagnostic["savedSession"], "absent")
        let missing = try await harness.request("session")
        XCTAssertEqual(missing.error, "signIn")
        try await harness.script(#"""
        document.cookie = 'ds_user_id=7; path=/';
        globalThis.pages = [
          {status:'ok',inbox:{threads:[{thread_id:'21',items:[{text:'Private fixture text'}]}]}},
          {status:'fail',message:'challenge_required'},
          {status:'ok'},
          {__http:401}
        ];
        """#)
        let savedHint = try await harness.request("sessionHint")
        XCTAssertEqual(savedHint.diagnostic["savedSession"], "present")
        let session = try await harness.request("session")
        XCTAssertNil(session.error)
        XCTAssertTrue(session.posts.isEmpty && session.stories.isEmpty && session.threads.isEmpty && session.messages.isEmpty)
        let challenge = try await harness.request("session")
        XCTAssertEqual(challenge.error, "signIn")
        let malformed = try await harness.request("session")
        XCTAssertEqual(malformed.error, "unsupported")
        let expired = try await harness.request("session")
        XCTAssertEqual(expired.error, "signIn")
        let safeReads = try await harness.script("return calls.length === 4 && calls.every(c => c.path === '/api/v1/direct_v2/inbox/?limit=1&thread_message_limit=1' && c.options.method === 'GET');") as? Bool
        XCTAssertEqual(safeReads, true)
    }

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

    func testTextSendIsExplicitBoundedAndRequiresServerAcknowledgement() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        document.cookie = 'csrftoken=fixture-csrf; path=/';
        globalThis.pages = [
          {inbox:{threads:[{thread_id:'21',items:[]}]}},
          {thread:{items:[]}},
          {status:'ok',payload:{item_id:'server-item'}},
          {status:'ok'},
          {__http:429}
        ];
        """#)
        let beforeOpen = try await harness.request("sendText",identifier:"21",message:"Hello")
        XCTAssertEqual(beforeOpen.error,"invalidMessage")
        _ = try await harness.request("inbox")
        _ = try await harness.request("thread",identifier:"21")
        let tooLong = try await harness.request("sendText",identifier:"21",message:String(repeating:"a",count:1001))
        XCTAssertEqual(tooLong.error,"invalidMessage")
        let sent = try await harness.request("sendText",identifier:"21",message:"Hello & goodbye + 🙂")
        XCTAssertNil(sent.error)
        XCTAssertEqual(sent.sentItemID,"server-item")
        let repeated = try await harness.request("sendText",identifier:"21",message:"Hello & goodbye + 🙂")
        XCTAssertEqual(repeated.sentItemID,"server-item")
        let body = try await harness.script("return new URLSearchParams(calls[2].options.body).get('text');") as? String
        XCTAssertEqual(body,"Hello & goodbye + 🙂")
        let count = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(count,3)
        let method = try await harness.script("return calls[2].options.method;") as? String
        XCTAssertEqual(method,"POST")
        let uncertain = try await harness.request("sendText",identifier:"21",message:"Another",context:"2234567890123456789")
        XCTAssertEqual(uncertain.error,"sendUnconfirmed")
        let limited = try await harness.request("sendText",identifier:"21",message:"Another",context:"3234567890123456789")
        XCTAssertEqual(limited.error,"rateLimited")
        XCTAssertEqual(limited.retryAfterSeconds,60)
    }

    func testConversationPaginationUsesExplicitCursorsAndKeepsRecipientMembership() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        document.cookie = 'ds_user_id=7; path=/';
        globalThis.pages = [
          {inbox:{threads:[{thread_id:'21'}],oldest_cursor:'next inbox',has_older:true}},
          {inbox:{threads:[{thread_id:'22'}],has_older:false}},
          {thread:{users:[{pk:8,username:'friend'}],items:[{item_id:'b',text:'New',user_id:8}],oldest_cursor:'older messages',has_older:true}},
          {thread:{items:[{item_id:'a',text:'Old',user_id:7}],has_older:false}}
        ];
        """#)
        let inbox = try await harness.request("inbox")
        XCTAssertTrue(inbox.hasMore)
        let more = try await harness.request("moreInbox")
        XCTAssertEqual(more.threads.map(\.id),["22"])
        XCTAssertFalse(more.hasMore)
        let thread = try await harness.request("thread",identifier:"21")
        XCTAssertEqual(thread.messages.first?.sender,"friend")
        XCTAssertTrue(thread.hasMore)
        let old = try await harness.request("olderMessages",identifier:"21")
        XCTAssertEqual(old.messages.first?.text,"Old")
        XCTAssertTrue(old.messages.first?.mine == true)
        XCTAssertFalse(old.hasMore)
        let paths = try await harness.script("return calls.map(c=>c.path);") as? [String]
        XCTAssertTrue(paths?[1].contains("cursor=next%20inbox") == true)
        XCTAssertTrue(paths?[3].contains("cursor=older%20messages") == true)
    }

    func testSendErrorEnvelopeIsReadBeforeHTTPRejectionAndStaysPrivate() async throws {
        let harness = AdapterHarness()
        try await harness.prepare()
        try await harness.script(#"""
        document.cookie = 'csrftoken=fixture-csrf; path=/';
        globalThis.pages = [
          {inbox:{threads:[{thread_id:'21'}]}}, {thread:{items:[]}},
          {__http:400,status:'fail',message:'challenge_required',challenge:{url:'PRIVATE CHALLENGE'}},
          {__http:400,status:'fail',message:'checkpoint_required'},
          {__http:400,status:'fail',error_type:'two_factor_required'},
          {__http:400,status:'fail',message:'login_required'},
          {__http:400,status:'fail',error_type:'rate_limit_error'},
          {__http:400,status:'fail',message:'feedback_required',feedback_message:'PRIVATE SERVER TEXT'},
          {__http:403,status:'fail',error_type:'sentry_block'},
          {__http:422,status:'fail',message:'PRIVATE MESSAGE',error_type:'PRIVATE TOKEN'},
          {__http:503,status:'fail',message:'PRIVATE MESSAGE'},
          {status:'ok'}
        ];
        """#)
        _ = try await harness.request("inbox")
        _ = try await harness.request("thread", identifier:"21")
        let cases = [("signIn","challenge_required"), ("signIn","checkpoint_required"),
                     ("signIn","two_factor_required"), ("signIn","login_required"),
                     ("rateLimited","rate_limit_error"), ("actionBlocked","feedback_required"),
                     ("actionBlocked","sentry_block"), ("sendRejected","unclassified"),
                     ("sendUnconfirmed","unclassified"), ("sendUnconfirmed","missing_receipt")]
        for (index, expected) in cases.enumerated() {
            let result = try await harness.request("sendText", identifier:"21", message:"PRIVATE DRAFT",
                                                   context:String(1_234_567_890_123_456_789 + index))
            XCTAssertEqual(result.error, expected.0)
            XCTAssertEqual(result.diagnostic["reason"], expected.1)
            XCTAssertNil(result.sentItemID)
            XCTAssertFalse(result.diagnostic.description.contains("PRIVATE"))
            XCTAssertTrue(result.messages.isEmpty && result.threads.isEmpty)
            if expected.0 == "rateLimited" { XCTAssertEqual(result.retryAfterSeconds, 60) }
        }
        let count = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(count, 12, "Each explicit operation dispatches once, with no hidden send retries")
    }

    func testProgressiveFailureTraceIncludesHTTPAndFingerprintButNoContent() async throws {
        let harness = AdapterHarness(); try await harness.prepare()
        try await harness.script(#"""
        document.cookie = 'csrftoken=PRIVATE_CSRF; path=/';
        globalThis.pages = [{inbox:{threads:[{thread_id:'21'}]}},{thread:{items:[]}},
          {__http:400,status:'fail',message:'PRIVATE_ERROR',error_type:'PRIVATE_TYPE'},
          {__http:400,status:'fail',message:'PRIVATE_ERROR',error_type:'PRIVATE_TYPE'}];
        """#)
        _ = try await harness.request("inbox")
        _ = try await harness.request("thread", identifier: "21")
        let first = try await harness.request("sendText", identifier: "21", message: "PRIVATE_DRAFT")
        let second = try await harness.request("sendText", identifier: "21", message: "PRIVATE_DRAFT", context: "2234567890123456789")
        XCTAssertEqual(first.error, "sendRejected")
        XCTAssertEqual(first.diagnostic["server_fingerprint"]?.count, 64)
        XCTAssertEqual(first.diagnostic["server_fingerprint"], second.diagnostic["server_fingerprint"])
        let send = harness.traces.filter { $0["operation"] == "sendText" }
        XCTAssertTrue(send.contains { $0["stage"] == "http_received" && $0["http"] == "400" })
        XCTAssertTrue(send.contains { $0["stage"] == "decoded" && $0["response_shape"]?.contains("message=string") == true })
        XCTAssertFalse(harness.traces.description.contains("PRIVATE"))
        let count = try await harness.script("return calls.length;") as? Int
        XCTAssertEqual(count, 4)
        let keySent = try await harness.script("return JSON.stringify(calls).includes('a'.repeat(64));") as? Bool
        XCTAssertEqual(keySent, false)
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
    private(set) var traces: [[String: String]] = []
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame:.zero,configuration:config)
        super.init()
        let sink = AdapterTraceSink(); sink.owner = self
        config.userContentController.add(sink, contentWorld: .defaultClient, name: "porchDiagnostics")
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
    func request(_ operation:String,identifier:String = "",message:String = "",context:String = "1234567890123456789") async throws -> InstagramDataResult {
        let path = try XCTUnwrap(Bundle.main.url(forResource:"instagram-data",withExtension:"js"))
        let source = try String(contentsOf:path,encoding:.utf8)
        let output = try await webView.callAsyncJavaScript(source,arguments:["operation":operation,"identifier":identifier,"messageText":message,"clientContext":context,"requestTraceID":UUID().uuidString,"diagnosticKey":String(repeating:"a",count:64)],in:nil,contentWorld:.defaultClient)
        let text = try XCTUnwrap(output as? String)
        return try JSONDecoder().decode(InstagramDataResult.self,from:Data(text.utf8))
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { ready?.resume(); ready = nil }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { ready?.resume(throwing:error); ready = nil }
    func receive(_ message: WKScriptMessage) {
        if let body = message.body as? [String: Any], let fields = body["fields"] as? [String: String] { traces.append(fields) }
    }
}
@MainActor private final class AdapterTraceSink: NSObject, WKScriptMessageHandler {
    weak var owner: AdapterHarness?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}
