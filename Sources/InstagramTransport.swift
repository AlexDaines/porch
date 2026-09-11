import Foundation
import WebKit

@MainActor
protocol InstagramTransport: AnyObject {
    func execute(_ operation: String, identifier: String, text: String, context: String) async throws -> InstagramDataResult
    func close()
}

// One request at a time owns adapter cursors and WebKit preparation. Closing invalidates
// queued and in-flight work so a previous session cannot populate the next session.
@MainActor
final class WebKitInstagramTransport: NSObject, InstagramTransport, WKNavigationDelegate {
    private let diagnostics: DiagnosticsLog
    private let transportID = UUID().uuidString
    private var activeRequestID: String?
    private var preparationStarted = Date()
    private var webView: WKWebView?
    private var preparation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var ready = false
    private var retryAfter = Date.distantPast
    private var generation = 0
    private var tail: Task<InstagramDataResult, Error>?
    private var tasks: [UUID: Task<InstagramDataResult, Error>] = [:]

    init(diagnostics: DiagnosticsLog = .shared) { self.diagnostics = diagnostics; super.init() }

    func execute(_ operation: String, identifier: String = "", text: String = "", context: String = "") async throws -> InstagramDataResult {
        let previous = tail
        let epoch = generation
        let id = UUID()
        let queued = Date()
        var fields = ["request_id": id.uuidString, "transport_id": transportID, "operation": operation,
                      "queue_depth": String(tasks.count), "generation": String(epoch)]
        if !identifier.isEmpty { fields["thread_ref"] = diagnostics.reference("identifier:" + identifier) }
        if !context.isEmpty { fields["context_ref"] = diagnostics.reference("context:" + context) }
        diagnostics.record(.requestQueued, fields)
        let task = Task { @MainActor in
            _ = try? await previous?.value
            var trace = fields
            trace["queue_ms"] = String(Int(Date().timeIntervalSince(queued) * 1_000))
            do {
                try Task.checkCancellation()
                guard epoch == self.generation else { throw CancellationError() }
                guard Date() >= self.retryAfter else { throw InstagramDataClient.ClientError.rateLimited }
                self.activeRequestID = id.uuidString
                self.diagnostics.record(.requestStarted, trace)
                if operation == "sendText" { await self.diagnostics.flush() }
                try Task.checkCancellation()
                guard epoch == self.generation else { throw CancellationError() }
                let needsContext = !self.ready || operation == "sendText"
                try await self.prepare()
                try Task.checkCancellation()
                guard epoch == self.generation else { throw CancellationError() }
                guard let view = self.webView,
                  let path = Bundle.main.url(forResource: "instagram-data", withExtension: "js") else { throw URLError(.cannotLoadFromNetwork) }
                if needsContext {
                    let log = self.diagnostics
                    let contextFields = ["request_id": id.uuidString, "transport_id": self.transportID,
                        "generation": String(epoch), "cookie_store": view.configuration.websiteDataStore.isPersistent ? "persistent" : "ephemeral"]
                    // Observation must not hold up dispatch. The event timestamp
                    // identifies when this asynchronous jar snapshot arrived.
                    view.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        log.record(.requestContext, contextFields.merging(Self.cookieDiagnostics(cookies)) { _, new in new })
                    }
                }
                let script = try String(contentsOf: path, encoding: .utf8)
                let started = Date()
                let value = try await view.callAsyncJavaScript(script, arguments: ["operation": operation, "identifier": identifier,
                    "messageText": text, "clientContext": context, "requestTraceID": id.uuidString,
                    "diagnosticKey": self.diagnostics.adapterDiagnosticKey], in: nil, contentWorld: .defaultClient)
                try Task.checkCancellation()
                guard epoch == self.generation else { throw CancellationError() }
                guard let string = value as? String, let data = string.data(using: .utf8), data.count <= 1_000_000 else { throw URLError(.cannotParseResponse) }
                let result = try JSONDecoder().decode(InstagramDataResult.self, from: data)
                trace.merge(result.diagnostic) { _, value in value }
                trace["bridge_ms"] = String(Int(Date().timeIntervalSince(started) * 1_000))
                trace["duration_ms"] = String(Int(Date().timeIntervalSince(queued) * 1_000))
                trace["result"] = result.error ?? "none"
                trace["posts"] = String(result.posts.count); trace["stories"] = String(result.stories.count)
                trace["threads"] = String(result.threads.count); trace["messages"] = String(result.messages.count)
                trace["has_more"] = String(result.hasMore)
                self.diagnostics.record(.requestCompleted, trace)
                if result.error == "rateLimited" {
                    self.retryAfter = Date().addingTimeInterval(Double(max(60, result.retryAfterSeconds ?? 60)))
                }
                if self.activeRequestID == id.uuidString { self.activeRequestID = nil }
                return result
            } catch {
                trace.merge(DiagnosticsLog.errorFields(error)) { _, value in value }
                trace["duration_ms"] = String(Int(Date().timeIntervalSince(queued) * 1_000))
                trace["result"] = error is CancellationError ? "cancelled" : InstagramDataClient.code(error)
                self.diagnostics.record(error is CancellationError ? .requestCancelled : .requestFailed, trace)
                if self.activeRequestID == id.uuidString { self.activeRequestID = nil }
                throw error
            }
        }
        tasks[id] = task
        tail = task
        defer { tasks[id] = nil; if tasks.isEmpty { tail = nil } }
        return try await task.value
    }

    // Cookie-jar metadata only; presence does not prove that a request sent it.
    // Values, domains, paths and expiry dates never enter the diagnostic object.
    nonisolated static func cookieDiagnostics(_ cookies: [HTTPCookie]) -> [String: String] {
        let instagram = cookies.filter {
            ["instagram.com", "www.instagram.com"].contains($0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) &&
            ($0.expiresDate == nil || $0.expiresDate! > Date())
        }
        let names = Set(instagram.map(\.name))
        return ["cookie_count": String(instagram.count), "session_cookie_present": String(names.contains("sessionid")),
                "csrf_cookie_present": String(names.contains("csrftoken")), "viewer_cookie_present": String(names.contains("ds_user_id")),
                "device_cookie_present": String(names.contains("ig_did")), "machine_cookie_present": String(names.contains("mid"))]
    }

    private func prepare() async throws {
        if ready { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.limitsNavigationsToAppBoundDomains = true
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.add(DiagnosticScriptSink { [weak self] traceID, fields in
            guard let self, traceID == self.activeRequestID else { return }
            var values = fields
            values["request_id"] = traceID; values["transport_id"] = self.transportID
            self.diagnostics.record(.adapterStage, values)
        }, contentWorld: .defaultClient, name: "porchDiagnostics")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        webView = view
        preparationStarted = Date()
        diagnostics.record(.webPrepare, ["transport_id": transportID, "generation": String(generation)])
        try await withCheckedThrowingContinuation { continuation in
            preparation = continuation
            view.loadHTMLString("<!doctype html><html><head><title>Porch</title></head><body></body></html>", baseURL: URL(string: "https://www.instagram.com/"))
            timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.failPreparation(URLError(.timedOut))
            }
        }
    }
    func close() {
        diagnostics.record(.transportClosed, ["transport_id": transportID, "queue_depth": String(tasks.count), "generation": String(generation)])
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll(); tail = nil
        failPreparation(CancellationError())
    }
    private func failPreparation(_ error: Error) {
        if preparation != nil {
            var fields = DiagnosticsLog.errorFields(error)
            fields["transport_id"] = transportID
            fields["prepare_ms"] = String(Int(Date().timeIntervalSince(preparationStarted) * 1_000))
            diagnostics.record(.webFailed, fields)
        }
        timeout?.cancel(); timeout = nil
        preparation?.resume(throwing: error); preparation = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil; ready = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        timeout?.cancel(); timeout = nil; ready = true
        diagnostics.record(.webReady, ["transport_id": transportID, "prepare_ms": String(Int(Date().timeIntervalSince(preparationStarted) * 1_000))])
        preparation?.resume(); preparation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === self.webView { failPreparation(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === self.webView { failPreparation(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView {
            diagnostics.record(.webTerminated, ["transport_id": transportID, "reason": "process_terminated"])
            close()
        }
    }
}

@MainActor
private final class DiagnosticScriptSink: NSObject, WKScriptMessageHandler {
    private let receive: (String, [String: String]) -> Void
    init(receive: @escaping (String, [String: String]) -> Void) { self.receive = receive }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let trace = body["trace"] as? String,
              UUID(uuidString: trace) != nil, let fields = body["fields"] as? [String: String], fields.count <= DiagnosticsLog.maximumFields else { return }
        receive(trace, DiagnosticsLog.sanitize(fields))
    }
}
