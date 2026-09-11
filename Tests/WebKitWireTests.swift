import XCTest
import WebKit
import Network
@testable import Porch

// Real WebKit HTTP requests, restricted to a loopback fixture and disposable
// cookies. This compares document loading modes, not Meta's private risk system,
// HTTPS/TLS, or Instagram's application scripts. No real account can enter it.
@MainActor
final class WebKitWireTests: XCTestCase {
    func testLocalDocumentAndOrdinaryPageSendConsistentBrowserHeaders() async throws {
        let server = try WireFixtureServer()
        try await server.start()
        defer { server.stop() }
        let origin = try XCTUnwrap(server.origin)
        var evidence: [[String: String]] = []
        var agents: [String] = []
        for local in [true, false] {
            let harness = WireWebView()
            defer { harness.close() }
            var stage = "prepare"
            do {
                try await harness.prepare(origin: origin, local: local)
                stage = "inbox"
                let inbox = try await harness.request("inbox", local: local)
                XCTAssertNil(inbox.error)
                stage = "thread"
                _ = try await harness.request("thread", local: local, identifier: "21")
                stage = "sendText"
                let sent = try await harness.request("sendText", local: local, identifier: "21", message: "Synthetic fixture only")
                XCTAssertNil(sent.error)
                XCTAssertEqual(sent.sentItemID, "fixture-receipt")
                stage = "validate_wire"
                let requests = server.takeRequests().filter { $0.path.hasPrefix("/api/") }
                XCTAssertEqual(requests.count, 3)
                let post = try XCTUnwrap(requests.last)
                XCTAssertEqual(post.method, "POST")
                XCTAssertEqual(post.headers["origin"], origin.absoluteString)
                XCTAssertTrue(post.headers["cookie"]?.contains("sessionid=fixture-session") == true)
                XCTAssertEqual(post.headers["x-csrftoken"], "fixture-csrf")
                XCTAssertEqual(post.headers["x-ig-www-claim"], "fixture-claim")
                XCTAssertEqual(post.headers["x-ig-app-id"], "936619743392459")
                XCTAssertFalse(post.body.contains(String(repeating: "a", count: 64)))
                agents.append(try XCTUnwrap(post.headers["user-agent"]))
                evidence.append([
                    "mode": local ? "local_client_world" : "loaded_page_world",
                    "post_origin_matches": String(post.headers["origin"] == origin.absoluteString),
                    "referrer_path": post.headers["referer"].flatMap(URL.init(string:))?.path ?? "missing",
                    "session_cookie_sent": String(post.headers["cookie"]?.contains("sessionid=fixture-session") == true),
                    "sec_fetch_site": post.headers["sec-fetch-site"] ?? "missing",
                    "sec_fetch_mode": post.headers["sec-fetch-mode"] ?? "missing",
                    "sec_fetch_dest": post.headers["sec-fetch-dest"] ?? "missing",
                    "ua_is_webkit": String(agents.last?.contains("AppleWebKit") == true),
                    "ua_has_safari_version": String(agents.last?.contains("Version/") == true),
                    "document_origin": inbox.diagnostic["document_origin"] ?? "missing",
                    "location_origin": inbox.diagnostic["location_origin"] ?? "missing",
                    "requests": String(requests.count)
                ])
            } catch {
                XCTFail("Loopback \(local ? "local_client_world" : "loaded_page_world") failed during \(stage); navigation \(harness.stage)")
                let context = ["mode": local ? "local_client_world" : "loaded_page_world", "stage": stage,
                    "navigation": harness.stage, "captured_requests": String(server.takeRequests().count)]
                let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
                attachment.name = "loopback-failure-context.json"; attachment.lifetime = .keepAlways; add(attachment)
                throw error
            }
        }
        XCTAssertEqual(agents[0], agents[1], "Document loading must not change the default WebKit identity")
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "loopback-request-comparison.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class WireWebView: NSObject, WKNavigationDelegate {
    private var view: WKWebView!
    private var navigation: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?
    private(set) var stage = "idle"
    func prepare(origin: URL, local: Bool) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = !local
        // The test host's app-bound allowlist contains Instagram, not localhost.
        // Both variants omit that navigation policy; production remains bound.
        view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        // A server sets the same disposable cookies for both variants, as a
        // sign-in page would. HTTPCookieStore writes to an IP cookie domain are
        // not a faithful way to establish this loopback browser session.
        stage = "bootstrap_page"
        try await navigate { view.load(URLRequest(url: origin.appendingPathComponent("page"))) }
        if local {
            stage = "local_document"
            try await navigate { view.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: origin.appendingPathComponent("")) }
        }
        stage = "ready"
    }
    private func navigate(_ load: () -> WKNavigation?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            watchdog = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.finish(URLError(.timedOut))
            }
            _ = load()
        }
    }
    func request(_ operation: String, local: Bool, identifier: String = "", message: String = "") async throws -> InstagramDataResult {
        let path = try XCTUnwrap(Bundle.main.url(forResource: "instagram-data", withExtension: "js"))
        let script = try String(contentsOf: path, encoding: .utf8)
        let result = try await view.callAsyncJavaScript(script, arguments: ["operation": operation, "identifier": identifier,
            "messageText": message, "clientContext": "1234567890123456789", "requestTraceID": UUID().uuidString,
            "diagnosticKey": String(repeating: "a", count: 64)], in: nil, contentWorld: local ? .defaultClient : .page)
        return try JSONDecoder().decode(InstagramDataResult.self, from: Data(try XCTUnwrap(result as? String).utf8))
    }
    func close() { watchdog?.cancel(); view.stopLoading(); view.navigationDelegate = nil; view = nil }
    private func finish(_ error: Error? = nil) {
        watchdog?.cancel()
        if let error { navigation?.resume(throwing: error) } else { navigation?.resume() }
        navigation = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}

private final class WireFixtureServer: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: String
    }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.alex.porch.wire-fixture")
    private let lock = NSLock()
    private var requests: [Request] = []
    var origin: URL? { listener.port.flatMap { URL(string: "http://127.0.0.1:\($0.rawValue)") } }
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.listener.stateUpdateHandler = nil; continuation.resume()
                case .failed(let error): self?.listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.receive(connection, buffered: Data())
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
    func takeRequests() -> [Request] { lock.withLock { let copy = requests; requests.removeAll(); return copy } }
    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffered; if let data { bytes.append(data) }
            guard error == nil, bytes.count < 262_144 else { connection.cancel(); return }
            guard let split = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if complete { connection.cancel() } else { self.receive(connection, buffered: bytes) }; return
            }
            let lines = String(decoding: bytes[..<split.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ")
            guard first.count >= 2 else { connection.cancel(); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            guard bytes.count - split.upperBound >= length else {
                if complete { connection.cancel() } else { self.receive(connection, buffered: bytes) }; return
            }
            let request = Request(method: String(first[0]), path: String(first[1]), headers: headers,
                body: String(decoding: bytes[split.upperBound...], as: UTF8.self))
            self.lock.withLock { self.requests.append(request) }
            let body: String
            if request.path.contains("broadcast/text") { body = #"{"status":"ok","payload":{"item_id":"fixture-receipt"}}"# }
            else if request.path.contains("/inbox/") { body = #"{"status":"ok","inbox":{"threads":[{"thread_id":"21"}]}}"# }
            else if request.path.contains("/threads/") { body = #"{"status":"ok","thread":{"items":[]}}"# }
            else { body = "<!doctype html><html><body></body></html>" }
            let mime = request.path.hasPrefix("/api/") ? "application/json" : "text/html"
            let cookies = mime == "text/html" ? "Set-Cookie: sessionid=fixture-session; Path=/; HttpOnly\r\nSet-Cookie: csrftoken=fixture-csrf; Path=/\r\n" : ""
            let response = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(body.utf8.count)\r\nX-IG-Set-WWW-Claim: fixture-claim\r\n\(cookies)Connection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
