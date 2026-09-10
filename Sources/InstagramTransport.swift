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
    private var webView: WKWebView?
    private var preparation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var ready = false
    private var retryAfter = Date.distantPast
    private var generation = 0
    private var tail: Task<InstagramDataResult, Error>?
    private var tasks: [UUID: Task<InstagramDataResult, Error>] = [:]

    func execute(_ operation: String, identifier: String = "", text: String = "", context: String = "") async throws -> InstagramDataResult {
        let previous = tail
        let epoch = generation
        let id = UUID()
        let task = Task { @MainActor in
            _ = try? await previous?.value
            try Task.checkCancellation()
            guard epoch == self.generation else { throw CancellationError() }
            guard Date() >= self.retryAfter else { throw InstagramDataClient.ClientError.rateLimited }
            try await self.prepare()
            guard let view = self.webView,
                  let path = Bundle.main.url(forResource: "instagram-data", withExtension: "js") else { throw URLError(.cannotLoadFromNetwork) }
            let script = try String(contentsOf: path, encoding: .utf8)
            let value = try await view.callAsyncJavaScript(script, arguments: ["operation": operation, "identifier": identifier, "messageText": text, "clientContext": context], in: nil, contentWorld: .defaultClient)
            try Task.checkCancellation()
            guard epoch == self.generation else { throw CancellationError() }
            guard let string = value as? String, let data = string.data(using: .utf8), data.count <= 1_000_000 else { throw URLError(.cannotParseResponse) }
            let result = try JSONDecoder().decode(InstagramDataResult.self, from: data)
            if result.error == "rateLimited" {
                self.retryAfter = Date().addingTimeInterval(Double(max(60,min(result.retryAfterSeconds ?? 60,86400))))
            }
            return result
        }
        tasks[id] = task
        tail = task
        defer { tasks[id] = nil; if tasks.isEmpty { tail = nil } }
        return try await task.value
    }

    private func prepare() async throws {
        if ready { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.limitsNavigationsToAppBoundDomains = true
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        webView = view
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
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll(); tail = nil
        failPreparation(CancellationError())
    }
    private func failPreparation(_ error: Error) {
        timeout?.cancel(); timeout = nil
        preparation?.resume(throwing: error); preparation = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil; ready = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        timeout?.cancel(); timeout = nil; ready = true
        preparation?.resume(); preparation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === self.webView { failPreparation(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === self.webView { failPreparation(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === self.webView { close() } }
}
