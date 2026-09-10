import XCTest
@testable import Porch

@MainActor
final class InstagramConnectionTests: XCTestCase {
    func testFreshSignInOpensImmediatelyAndCancelDoesNotConnect() async throws {
        let browser = AuthenticationStub()
        let transport = SessionStub()
        let connection = InstagramConnection(browser: browser, transport: transport)
        connection.start()
        XCTAssertEqual(connection.phase, .signingIn)
        XCTAssertEqual(browser.opens, 1)
        XCTAssertEqual(transport.requests, 0)
        connection.checkSignIn()
        try await settle { !connection.checking }
        XCTAssertNotNil(connection.failure)
        XCTAssertEqual(connection.phase, .signingIn)
        XCTAssertEqual(transport.requests, 0)
        connection.cancel()
        XCTAssertEqual(connection.phase, .idle)
        connection.start()
        XCTAssertEqual(browser.opens, 2)
    }

    func testExistingSessionNeedsServerVerificationAndExpiredSessionOpensSignIn() async throws {
        let browser = AuthenticationStub(saved: true)
        let transport = SessionStub()
        let connection = InstagramConnection(browser: browser, transport: transport)
        await connection.refreshSavedSession()
        connection.start()
        try await settle { transport.requests == 1 }
        XCTAssertEqual(connection.phase, .idle, "A cookie alone is not proof of authentication")
        XCTAssertTrue(connection.checking)
        XCTAssertEqual(browser.opens, 0)
        transport.complete(.init(error: "signIn"))
        try await settle { connection.phase == .signingIn }
        XCTAssertEqual(browser.opens, 1)
        connection.checkSignIn()
        try await settle { transport.requests == 2 }
        transport.complete(.init(error: "signIn"))
        try await settle { !connection.checking }
        browser.onPossibleSignIn?()
        try await settle { transport.requests == 3 }
        transport.complete(.init())
        try await settle { connection.phase == .connected }
    }

    func testLateSuccessAfterCancelCannotEnterTheApp() async throws {
        let browser = AuthenticationStub(saved: true)
        let transport = SessionStub()
        let connection = InstagramConnection(browser: browser, transport: transport)
        connection.signIn()
        browser.onPossibleSignIn?()
        try await settle { transport.requests == 1 }
        connection.cancel()
        transport.complete(.init())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(connection.phase, .idle)
        XCTAssertFalse(connection.checking)
    }

    func testFailureRetainsSignInAndOnlyExplicitActionRetries() async throws {
        let browser = AuthenticationStub(saved: true)
        let transport = SessionStub()
        let connection = InstagramConnection(browser: browser, transport: transport)
        connection.signIn()
        browser.onPossibleSignIn?()
        try await settle { transport.requests == 1 }
        transport.complete(.init(error: "offline"))
        try await settle { !connection.checking }
        XCTAssertEqual(connection.phase, .signingIn)
        XCTAssertNotNil(connection.failure)
        browser.onPossibleSignIn?()
        XCTAssertEqual(transport.requests, 1)
        connection.checkSignIn()
        try await settle { transport.requests == 2 }
        transport.complete(.init(error: "signIn"))
        try await settle { !connection.checking }
        browser.onPossibleSignIn?()
        try await settle { transport.requests == 3 }
        transport.complete(.init())
        try await settle { connection.phase == .connected }
    }

    private func settle(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class AuthenticationStub: InstagramAuthentication {
    var onPossibleSignIn: (() -> Void)?
    var saved: Bool
    var opens = 0
    init(saved: Bool = false) { self.saved = saved }
    func hasSavedSession() async -> Bool { saved }
    func connect() { opens += 1 }
    func suspend() {}
}

@MainActor
private final class SessionStub: InstagramTransport {
    var requests = 0
    private var pending: CheckedContinuation<InstagramDataResult, Error>?
    func execute(_ operation: String, identifier: String, text: String, context: String) async throws -> InstagramDataResult {
        XCTAssertEqual(operation, "session")
        requests += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func complete(_ result: InstagramDataResult) { pending?.resume(returning: result); pending = nil }
    // Deliberately allows a late result to exercise cancellation at the coordinator boundary.
    func close() {}
}
