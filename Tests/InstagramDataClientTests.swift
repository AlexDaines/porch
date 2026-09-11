import XCTest
@testable import Porch

@MainActor
final class InstagramDataClientTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName:"porch.tests."+UUID().uuidString)! }
    private func post(_ id: String) -> InstagramPost { InstagramPost(id:id,username:"fixture",caption:"Fixture",timestamp:1,media:[]) }

    func testSendTraceSurvivesRestartAndReconciliationWithoutContentOrRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = defaults(), log = DiagnosticsLog(directory: directory), transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"PRIVATE_NAME",preview:"")]), .init(error:"sendUnconfirmed")]
        let client = InstagramDataClient(transport:transport,defaults:store,diagnostics:log)
        await client.load(.messages)
        _ = await client.sendText("PRIVATE_DRAFT",to:"21")
        let attempt = try XCTUnwrap(client.pendingSends["21"])
        let nextTransport = StubTransport()
        nextTransport.results = [.init(messages:[.init(id:"PRIVATE_ITEM",text:"PRIVATE_DRAFT",mine:true,context:attempt.context)])]
        let nextLog = DiagnosticsLog(directory:directory)
        let next = InstagramDataClient(transport:nextTransport,defaults:store,diagnostics:nextLog)
        _ = try await next.request("thread",identifier:"21")
        XCTAssertNil(next.pendingSends["21"])
        XCTAssertEqual(transport.calls.filter { $0 == "sendText" }.count,1)
        XCTAssertEqual(nextTransport.calls,["thread"])
        await nextLog.flush()
        let snapshot = await log.snapshot()
        let events = snapshot.entries.filter { $0.event.rawValue.hasPrefix("send") }
        for event in [DiagnosticsLog.Event.sendPrepared,.sendDispatched,.sendUnconfirmed,.sendRestored,.sendReconciled,.sendWarningCleared] {
            XCTAssertTrue(events.contains { $0.event == event }, "Missing \(event)")
        }
        XCTAssertTrue(events.allSatisfy { $0.fields["attempt_id"] == attempt.traceID })
        XCTAssertFalse(events.description.contains("PRIVATE"))
        XCTAssertFalse(events.description.contains(attempt.context))
    }

    func testLegacySendJournalStillRestoresWithoutTraceID() throws {
        let store = defaults()
        store.set(Data(#"{"21":{"context":"1234567890123456789","started":0}}"#.utf8),forKey:"porch.pending-sends.v1")
        let client = InstagramDataClient(transport:StubTransport(),defaults:store)
        XCTAssertEqual(client.pendingSends["21"]?.context,"1234567890123456789")
        XCTAssertNil(client.pendingSends["21"]?.traceID)
    }

    func testRefreshAndPaginationFailuresKeepContentAndCursorAvailable() async {
        let transport = StubTransport()
        transport.results = [.init(posts:[post("1")],hasMore:true), .init(error:"offline"), .init(error:"rateLimited")]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.feed)
        await client.load(.feed,refresh:true)
        XCTAssertEqual(client.posts.map(\.id),["1"])
        XCTAssertTrue(client.hasMore && client.hasLoadedCurrentTab)
        XCTAssertEqual(client.error,"offline")
        await client.morePosts()
        XCTAssertEqual(client.posts.map(\.id),["1"])
        XCTAssertTrue(client.hasMore)
        XCTAssertEqual(client.moreError,"rateLimited")
    }
    func testLateRequestCannotRepopulateClosedSession() async {
        let transport = StubTransport(); transport.hold = true
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        let task = Task { await client.load(.feed) }
        await transport.waitForPending()
        client.close()
        transport.resume(.init(posts:[post("old")]))
        await task.value
        XCTAssertTrue(client.posts.isEmpty)
        XCTAssertFalse(client.loading)
        XCTAssertNil(client.error)
    }
    func testBackgroundTabFailureDoesNotReplaceSelectedCachedFeed() async {
        let transport = StubTransport(); transport.results = [.init(posts:[post("1")])]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.feed)
        transport.hold = true
        let task = Task { await client.load(.stories) }
        await transport.waitForPending()
        await client.load(.feed)
        transport.resume(.init(error:"offline"))
        await task.value
        XCTAssertNil(client.error)
        XCTAssertFalse(client.loading)
        XCTAssertEqual(client.posts.count,1)
    }
    func testUnconfirmedSendSurvivesRestartWithoutStoringMessageBody() async {
        let store = defaults(); let transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")]),.init(error:"sendUnconfirmed")]
        let client = InstagramDataClient(transport:transport,defaults:store)
        await client.load(.messages)
        let outcome = await client.sendText("PRIVATE FIXTURE TEXT",to:"21")
        XCTAssertEqual(outcome,"sendUnconfirmed")
        XCTAssertNotNil(client.pendingSends["21"])
        let data = store.data(forKey:"porch.pending-sends.v1")!
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("PRIVATE FIXTURE TEXT"))
        let restartedTransport = StubTransport()
        restartedTransport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")])]
        let restarted = InstagramDataClient(transport:restartedTransport,defaults:store)
        await restarted.load(.messages)
        let second = await restarted.sendText("PRIVATE FIXTURE TEXT",to:"21")
        XCTAssertEqual(second,"sendUnconfirmed")
        XCTAssertEqual(restartedTransport.calls,["inbox"])
        restarted.clearJournal()
        XCTAssertNil(store.data(forKey:"porch.pending-sends.v1"))
    }
    func testRepeatedSendTapDispatchesOnceAndAcknowledgementClearsJournal() async {
        let transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")])]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.messages)
        transport.hold = true
        let first = Task { await client.sendText("Hello",to:"21") }
        await transport.waitForPending()
        let repeated = await client.sendText("Hello",to:"21")
        XCTAssertEqual(repeated,"sendUnconfirmed")
        XCTAssertEqual(transport.calls.filter { $0 == "sendText" }.count,1)
        transport.resume(.init(sentItemID:"server-item"))
        let success = await first.value
        XCTAssertNil(success)
        XCTAssertNil(client.pendingSends["21"])
        XCTAssertTrue(client.sendingThreads.isEmpty)
    }
    func testSendNeedsReceiptAndValidAcceptedRecipient() async {
        let transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")]),.init()]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.messages)
        for (message,thread) in [("Hello","22"),(" ","21"),(String(repeating:"🙂",count:501),"21")] {
            let failure = await client.sendText(message,to:thread)
            XCTAssertEqual(failure,"invalidMessage")
        }
        XCTAssertEqual(transport.calls.count,1)
        let outcome = await client.sendText("Hello",to:"21")
        XCTAssertEqual(outcome,"sendUnconfirmed")
        XCTAssertNotNil(client.pendingSends["21"])
    }
    func testRateLimitUsesServerDelayAndDoesNotRetryAutomatically() async {
        let transport = StubTransport(); transport.results = [.init(error:"rateLimited",retryAfterSeconds:300),.init()]
        var date = Date()
        let client = InstagramDataClient(transport:transport,defaults:defaults(),now:{date})
        await client.load(.feed)
        date = date.addingTimeInterval(61)
        await client.load(.stories)
        XCTAssertEqual(transport.calls.count,1)
        XCTAssertEqual(client.error,"rateLimited")
        date = date.addingTimeInterval(240)
        await client.load(.stories)
        XCTAssertEqual(transport.calls.count,2)
        XCTAssertNil(client.error)
    }

    func testRejectedSendKeepsDraftAndDiagnosticAfterConversationRefresh() async throws {
        let transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")]),
                             .init(error:"actionBlocked",diagnostic:["http":"400","reason":"feedback_required","message":"PRIVATE SERVER TEXT"]),
                             .init(diagnostic:["http":"200"])]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.messages)
        client.keepDraft("PRIVATE DRAFT", for:"21")
        let outcome = await client.sendText("PRIVATE DRAFT",to:"21")
        XCTAssertEqual(outcome,"actionBlocked")
        XCTAssertNil(client.pendingSends["21"], "Explicit refusal resolves the attempt, without retrying")
        XCTAssertEqual(client.drafts["21"],"PRIVATE DRAFT")
        _ = try await client.request("thread",identifier:"21")
        XCTAssertTrue(client.diagnostic.contains("HTTP: 200"))
        XCTAssertTrue(client.lastSendDiagnostic?.contains("HTTP: 400") == true)
        XCTAssertTrue(client.lastSendDiagnostic?.contains("Reason: feedback_required") == true)
        XCTAssertFalse(client.lastSendDiagnostic?.contains("PRIVATE") == true)
        XCTAssertEqual(transport.calls,["inbox","sendText","thread"])
        client.clearJournal()
        XCTAssertNil(client.lastSendDiagnostic)
    }

    func testDiagnosticRejectsUnexpectedServerReason() async {
        let transport = StubTransport()
        transport.results = [.init(threads:[.init(id:"21",title:"Fixture",preview:"")]),
                             .init(error:"sendRejected",diagnostic:["http":"400","reason":"PRIVATE TOKEN"])]
        let client = InstagramDataClient(transport:transport,defaults:defaults())
        await client.load(.messages)
        _ = await client.sendText("PRIVATE DRAFT",to:"21")
        XCTAssertTrue(client.lastSendDiagnostic?.contains("Reason: none") == true)
        XCTAssertFalse(client.lastSendDiagnostic?.contains("PRIVATE") == true)
    }
}

@MainActor
private final class StubTransport: InstagramTransport {
    var results: [InstagramDataResult] = []
    var calls: [String] = []
    var hold = false
    private var pending: CheckedContinuation<InstagramDataResult,Error>?
    func execute(_ operation:String,identifier:String,text:String,context:String) async throws -> InstagramDataResult {
        calls.append(operation)
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return results.removeFirst()
    }
    func close() { }
    func resume(_ value:InstagramDataResult) { pending?.resume(returning:value); pending = nil }
    func waitForPending() async {
        for _ in 0..<100 { if pending != nil { return }; try? await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Request did not start")
    }
}
