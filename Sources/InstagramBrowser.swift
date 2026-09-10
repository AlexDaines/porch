import SwiftUI
import WebKit

// Only the sign-in sheet uses Instagram's renderer. Reading uses InstagramDataClient.
@MainActor
final class InstagramBrowser: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var loading = false
    @Published private(set) var authenticated = false
    @Published private(set) var failure: String?
    @Published private(set) var clearingWebsiteData = false
    private(set) var webView: WKWebView?

    func connect() {
        guard !clearingWebsiteData else { return }
        suspend()
        authenticated = false; failure = nil; loading = true
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.limitsNavigationsToAppBoundDomains = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = self
        view.isOpaque = false; view.backgroundColor = .black
        webView = view
        view.load(URLRequest(url:NavigationPolicy.login,timeoutInterval:25))
    }
    func suspend() {
        webView?.stopLoading(); webView?.pauseAllMediaPlayback(); webView?.navigationDelegate = nil
        webView = nil; loading = false
    }
    func clearWebsiteData() async {
        guard !clearingWebsiteData else { return }
        clearingWebsiteData = true
        defer { clearingWebsiteData = false }
        suspend()
        await WKWebsiteDataStore.default().removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:.distantPast)
        URLCache.shared.removeAllCachedResponses()
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let url = action.request.url, NavigationPolicy.classify(url) == .allow else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { if webView === self.webView { loading = true } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loading = false
        if let path = webView.url?.path, path == "/" || path.hasPrefix("/direct/") { authenticated = true }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === self.webView { fail(error) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === self.webView { fail(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === self.webView { loading = false; failure = "Couldn't open Instagram." } }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; failure = "Couldn't open Instagram."
    }
}
struct InstagramWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context:Context)->WKWebView { webView }
    func updateUIView(_ view:WKWebView,context:Context) {}
}
struct InstagramSignIn: View {
    @ObservedObject var browser: InstagramBrowser
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("instagram.com").font(PorchTheme.body)
                Spacer()
                Button("Done") { dismiss() }.frame(minHeight:44)
            }.padding(.horizontal,16)
            PorchRule()
            if browser.loading { ProgressView().padding(8).accessibilityLabel("Loading Instagram sign-in") }
            if let failure = browser.failure {
                Text(failure).foregroundStyle(PorchTheme.muted).padding(30)
                Button("Try again") { browser.connect() }.frame(minHeight:44)
                Spacer()
            } else if let view = browser.webView { InstagramWebView(webView:view) }
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).porchSheet()
    }
}
