import SwiftUI
import WebKit

// Only authentication uses Instagram's renderer. Reading uses the local data transport.
@MainActor
final class InstagramBrowser: NSObject, ObservableObject, InstagramAuthentication, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var notice: String?
    @Published private(set) var clearingWebsiteData = false
    @Published private(set) var webView: WKWebView?
    var onPossibleSignIn: (() -> Void)?
    private var urlObservation: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?
    private let sessionProbe: WebKitInstagramTransport
    private let diagnostics: DiagnosticsLog
    private var pageStarted = Date()

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
        sessionProbe = WebKitInstagramTransport(diagnostics: diagnostics)
        super.init()
    }

    func hasSavedSession() async -> Bool {
        // A fresh process can report an empty WK cookie store until an app-bound
        // view is initialized. This local-only probe loads no Instagram page.
        let result = try? await sessionProbe.execute("sessionHint")
        return result?.diagnostic["savedSession"] == "present"
    }
    func connect() {
        guard !clearingWebsiteData else { return }
        suspend()
        failure = nil; notice = nil
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.limitsNavigationsToAppBoundDomains = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.isOpaque = false; view.backgroundColor = .black
        view.accessibilityIdentifier = "instagram-sign-in-web"
        webView = view
        config.websiteDataStore.httpCookieStore.add(self)
        urlObservation = view.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in self?.considerSignIn(view) }
        }
        beginLoading(view)
        view.load(URLRequest(url: NavigationPolicy.login, timeoutInterval: 25))
    }
    func suspend() {
        sessionProbe.close()
        timeout?.cancel(); timeout = nil
        urlObservation?.invalidate(); urlObservation = nil
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView?.stopLoading(); webView?.pauseAllMediaPlayback(); webView?.navigationDelegate = nil
        webView = nil; loading = false
    }
    func clearWebsiteData() async {
        guard !clearingWebsiteData else { return }
        clearingWebsiteData = true
        diagnostics.record(.authClear, ["stage": "preparing"])
        defer { clearingWebsiteData = false }
        suspend()
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        URLCache.shared.removeAllCachedResponses()
        diagnostics.record(.authClear, ["stage": "completed"])
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        if webView != nil { diagnostics.record(.authCookiesChanged); onPossibleSignIn?() }
    }
    private func considerSignIn(_ view: WKWebView) {
        guard view === webView, let url = view.url, NavigationPolicy.classify(url) == .allow else { return }
        if url.path == "/" || url.path.hasPrefix("/direct/") || url.path.hasPrefix("/accounts/onetap/") {
            onPossibleSignIn?()
        }
    }
    private func beginLoading(_ view: WKWebView) {
        timeout?.cancel()
        loading = true
        pageStarted = Date()
        diagnostics.record(.authPageStarted)
        timeout = Task { @MainActor [weak self, weak view] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let view, view === self.webView else { return }
            view.stopLoading()
            self.loading = false
            self.failure = "Instagram took too long to open."
            self.diagnostics.record(.authPageFailed, ["reason": "timeout", "duration_ms": String(Date().timeIntervalSince(self.pageStarted) * 1_000)])
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        let allowed = action.request.url.map { NavigationPolicy.classify($0) == .allow } ?? false
        diagnostics.record(.authNavigation, ["navigation": Self.navigationClass(action.request.url),
            "decision": allowed ? (action.targetFrame == nil ? "new_window" : "allow") : "cancel"])
        guard let url = action.request.url, NavigationPolicy.classify(url) == .allow else {
            notice = "Use your Instagram username and password here. External sign-in options aren't supported yet."
            decisionHandler(.cancel); return
        }
        // Links that request a new window still belong in this authentication view.
        if action.targetFrame == nil { decisionHandler(.cancel); webView.load(action.request); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { beginLoading(webView) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        timeout?.cancel(); timeout = nil; loading = false
        diagnostics.record(.authPageFinished, ["navigation": Self.navigationClass(webView.url),
            "duration_ms": String(Date().timeIntervalSince(pageStarted) * 1_000)])
        considerSignIn(webView)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            diagnostics.record(.authNavigation, ["http": String(http.statusCode), "navigation": Self.navigationClass(http.url)])
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === self.webView { fail(error) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === self.webView { fail(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView {
            diagnostics.record(.authPageFailed, ["reason": "process_terminated"])
            fail(URLError(.cannotLoadFromNetwork))
        }
    }
    private func fail(_ error: Error) {
        diagnostics.record(.authPageFailed, DiagnosticsLog.errorFields(error).merging(
            ["duration_ms": String(Date().timeIntervalSince(pageStarted) * 1_000)], uniquingKeysWith: { _, new in new }))
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        timeout?.cancel(); timeout = nil; loading = false
        failure = "Couldn't open Instagram. Check your connection and try again."
    }
    static func navigationClass(_ url: URL?) -> String {
        guard let url else { return "invalid" }
        guard url.host == "www.instagram.com" || url.host == "instagram.com" else { return "external" }
        let path = url.path.lowercased()
        if path.hasPrefix("/accounts/login") { return "login" }
        if path.hasPrefix("/challenge") { return "challenge" }
        if path.hasPrefix("/checkpoint") { return "checkpoint" }
        if path.contains("/two_factor") { return "two_factor" }
        if path.hasPrefix("/accounts/onetap") { return "one_tap" }
        if path.hasPrefix("/direct/") { return "direct" }
        return path == "/" ? "home" : "instagram_other"
    }
}
struct InstagramWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
struct InstagramSignIn: View {
    @ObservedObject var browser: InstagramBrowser
    @ObservedObject var connection: InstagramConnection
    var body: some View {
        VStack(spacing: 0) {
            PorchSheetHeader(title: "instagram.com", closeLabel: "Cancel sign-in") { connection.cancel() }
            PorchRule()
            if let failure = browser.failure {
                Spacer()
                VStack(spacing: 16) {
                    Text(failure).font(PorchTheme.body).foregroundStyle(PorchTheme.muted)
                    Button("Try again") { connection.signIn() }.buttonStyle(PorchButtonStyle())
                        .accessibilityIdentifier("sign-in-retry")
                }.padding(24).multilineTextAlignment(.center)
                Spacer()
            } else {
                if browser.loading { ProgressView().padding(8).accessibilityLabel("Loading Instagram sign-in") }
                if let view = browser.webView {
                    InstagramWebView(webView: view).id(ObjectIdentifier(view))
                }
                PorchRule()
                VStack(spacing: 4) {
                    if connection.checking {
                        ProgressView().frame(minHeight: 44).accessibilityLabel("Checking Instagram sign-in")
                    } else if let message = connection.failure {
                        Text(message).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                        Button("Try connection again") { connection.checkSignIn() }
                            .buttonStyle(PorchButtonStyle()).accessibilityIdentifier("sign-in-continue")
                    } else {
                        Text(browser.notice ?? "Sign in above to open Porch.")
                            .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted).frame(minHeight: 44)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8).multilineTextAlignment(.center)
            }
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).porchSheet()
    }
}
