import XCTest
@testable import Porch

@MainActor
final class FeedPaginationTests: XCTestCase {
    private func posts(_ range: ClosedRange<Int>) -> [InstagramPost] {
        range.map { InstagramPost(id: String($0), username: "fictional", caption: "", timestamp: 0, media: []) }
    }
    private func client(_ transport: FeedTransport) -> InstagramDataClient {
        InstagramDataClient(transport: transport, defaults: UserDefaults(suiteName: "porch.feed-tests." + UUID().uuidString)!)
    }
    func testInitialOverflowIsRevealedOnlyByChoiceEvenAfterServerEnd() async {
        let transport = FeedTransport([.init(posts: posts(1...18) + posts(1...2))])
        let client = client(transport)
        await client.load(.feed)
        XCTAssertEqual(client.posts.map(\.id), posts(1...10).map(\.id))
        XCTAssertEqual(client.feedBatchOptions, [5, 8])
        await client.morePosts(count: 5)
        XCTAssertEqual(client.posts.count, 15)
        XCTAssertEqual(client.feedBatchOptions, [3])
        await client.morePosts(count: 3)
        XCTAssertEqual(client.posts.map(\.id), posts(1...18).map(\.id))
        XCTAssertFalse(client.hasMore)
        XCTAssertFalse(client.reachedSessionLimit)
        XCTAssertEqual(transport.calls, ["feed"])
    }
    func testTwentyUsesOneRequestAndRetainsEveryOverflowPost() async {
        let transport = FeedTransport([.init(posts: posts(1...2), hasMore: true), .init(posts: posts(3...27))])
        let client = client(transport)
        await client.load(.feed)
        await client.morePosts(count: 20)
        XCTAssertEqual(client.posts.map(\.id), posts(1...22).map(\.id))
        XCTAssertEqual(client.lastFeedBatch?.added, 20)
        XCTAssertEqual(transport.counts, [10, 20])
        XCTAssertTrue(client.hasMore)
        await client.morePosts(count: 5)
        XCTAssertEqual(client.posts.map(\.id), posts(1...27).map(\.id))
        XCTAssertEqual(transport.calls, ["feed", "moreFeed"])
        XCTAssertFalse(client.hasMore)
    }
    func testBufferedPostsReduceRequestAndDeduplicateAcrossPages() async {
        let transport = FeedTransport([.init(posts: posts(1...13), hasMore: true), .init(posts: posts(12...16))])
        let client = client(transport)
        await client.load(.feed)
        await client.morePosts(count: 5)
        XCTAssertEqual(transport.counts, [10, 2])
        XCTAssertEqual(client.posts.map(\.id), posts(1...15).map(\.id))
        XCTAssertEqual(client.feedBatchOptions, [1])
        await client.morePosts(count: 1)
        XCTAssertEqual(client.posts.map(\.id), posts(1...16).map(\.id))
        XCTAssertEqual(transport.calls.count, 2)
    }
    func testShortAndDuplicateOnlyPagesStopWithoutChasingCount() async {
        let transport = FeedTransport([.init(posts: posts(1...1), hasMore: true),
            .init(posts: posts(1...1), hasMore: true), .init(posts: posts(2...3))])
        let client = client(transport)
        await client.load(.feed)
        await client.morePosts(count: 20)
        XCTAssertEqual(client.lastFeedBatch?.added, 0)
        XCTAssertEqual(transport.calls.count, 2)
        XCTAssertTrue(client.hasMore)
        await client.morePosts(count: 20)
        XCTAssertEqual(client.lastFeedBatch?.added, 2)
        XCTAssertEqual(client.posts.count, 3)
        XCTAssertFalse(client.hasMore)
        XCTAssertEqual(transport.calls.count, 3)
    }
    func testFailureKeepsBufferAtomicSoRetryCannotExceedChoice() async {
        let transport = FeedTransport([.init(posts: posts(1...13), hasMore: true), .init(error: "offline"), .init(posts: posts(14...15))])
        let client = client(transport)
        await client.load(.feed)
        await client.morePosts(count: 5)
        XCTAssertEqual(client.posts.count, 10)
        XCTAssertEqual(client.moreError, "offline")
        XCTAssertNil(client.lastFeedBatch)
        XCTAssertEqual(client.feedRetryCount, 5)
        // Returning to a cached feed must restore the failed choice rather than
        // the view's default. Retry remains the original five-post action.
        await client.load(.feed)
        await client.morePosts(count: client.feedRetryCount)
        XCTAssertEqual(client.posts.map(\.id), posts(1...15).map(\.id))
        XCTAssertEqual(transport.counts, [10, 2, 2])
        XCTAssertNil(client.moreError)
    }
    func testRemainingCapacityIsOfferedAndTechnicalLimitIsExplicit() async {
        let transport = FeedTransport([.init(posts: posts(1...198), hasMore: true), .init(posts: posts(199...210))])
        let client = client(transport)
        await client.load(.feed)
        for _ in 0..<9 { await client.morePosts(count: 20) }
        await client.morePosts(count: 5)
        XCTAssertEqual(client.posts.count, 195)
        XCTAssertEqual(client.feedBatchOptions, [5])
        await client.morePosts(count: 5)
        XCTAssertEqual(transport.counts, [10, 2])
        XCTAssertEqual(client.posts.map(\.id), posts(1...200).map(\.id))
        XCTAssertTrue(client.reachedSessionLimit)
        XCTAssertFalse(client.hasMore)
        XCTAssertTrue(client.feedBatchOptions.isEmpty)
        await client.morePosts(count: 5)
        XCTAssertEqual(transport.calls.count, 2)
    }
    func testRefreshFailurePreservesPendingAndSuccessReplacesIt() async {
        let transport = FeedTransport([.init(posts: posts(1...18)), .init(error: "offline"), .init(posts: posts(100...111))])
        let client = client(transport)
        await client.load(.feed)
        await client.load(.feed, refresh: true)
        await client.morePosts(count: 5)
        XCTAssertEqual(client.posts.map(\.id), posts(1...15).map(\.id))
        await client.load(.feed, refresh: true)
        XCTAssertEqual(client.posts.map(\.id), posts(100...109).map(\.id))
        XCTAssertNil(client.lastFeedBatch)
        await client.morePosts(count: 2)
        XCTAssertEqual(client.posts.map(\.id), posts(100...111).map(\.id))
        XCTAssertEqual(transport.calls, ["feed", "feed", "feed"])
    }
    func testRefreshWaitsForBatchAndRepeatedChoicesCannotOverlap() async {
        let transport = FeedTransport([.init(posts: posts(1...1), hasMore: true), .init(posts: posts(100...100))])
        let client = client(transport)
        await client.load(.feed)
        transport.holdNext = true
        let batch = Task { await client.morePosts(count: 5) }
        await transport.waitForPending()
        await client.morePosts(count: 10)
        let refresh = Task { await client.load(.feed, refresh: true) }
        await waitUntil { client.loading }
        XCTAssertEqual(transport.calls, ["feed", "moreFeed"])
        transport.resume(.init(posts: posts(2...8), hasMore: true))
        await batch.value; await refresh.value
        XCTAssertEqual(transport.calls, ["feed", "moreFeed", "feed"])
        XCTAssertEqual(client.posts.map(\.id), ["100"])
        XCTAssertFalse(client.hasMore || client.moreLoading || client.loading)
    }
    func testPaginationCannotBeginDuringRefresh() async {
        let transport = FeedTransport([.init(posts: posts(1...1), hasMore: true)])
        let client = client(transport)
        await client.load(.feed)
        transport.holdNext = true
        let refresh = Task { await client.load(.feed, refresh: true) }
        await transport.waitForPending()
        await client.morePosts(count: 5)
        XCTAssertEqual(transport.calls, ["feed", "feed"])
        transport.resume(.init(posts: posts(100...100)))
        await refresh.value
        XCTAssertEqual(client.posts.map(\.id), ["100"])
    }
    func testCloseWhileRefreshWaitsCannotRepopulateOrStartAnotherRequest() async {
        let transport = FeedTransport([.init(posts: posts(1...1), hasMore: true)])
        let client = client(transport)
        await client.load(.feed)
        transport.holdNext = true
        let batch = Task { await client.morePosts(count: 5) }
        await transport.waitForPending()
        let refresh = Task { await client.load(.feed, refresh: true) }
        await waitUntil { client.loading }
        client.close()
        transport.resume(.init(posts: posts(2...8), hasMore: true))
        await batch.value; await refresh.value
        XCTAssertTrue(client.posts.isEmpty && client.feedBatchOptions.isEmpty)
        XCTAssertFalse(client.moreLoading || client.loading || client.hasMore)
        XCTAssertNil(client.lastFeedBatch)
        XCTAssertEqual(transport.calls, ["feed", "moreFeed"])
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 { if condition() { return }; try? await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Expected state was not reached")
    }
}

@MainActor
private final class FeedTransport: InstagramTransport {
    var results: [InstagramDataResult]
    var calls: [String] = []
    var counts: [Int] = []
    var holdNext = false
    private var pending: CheckedContinuation<InstagramDataResult, Never>?
    init(_ results: [InstagramDataResult]) { self.results = results }
    func execute(_ operation: String, identifier: String, text: String, context: String, feedCount: Int) async throws -> InstagramDataResult {
        calls.append(operation); counts.append(feedCount)
        if holdNext { holdNext = false; return await withCheckedContinuation { pending = $0 } }
        guard !results.isEmpty else { XCTFail("Unexpected request"); return .init(error: "unavailable") }
        return results.removeFirst()
    }
    func close() {}
    func resume(_ result: InstagramDataResult) { pending?.resume(returning: result); pending = nil }
    func waitForPending() async {
        for _ in 0..<100 { if pending != nil { return }; try? await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Expected request was not started")
    }
}
