import SwiftUI
import WebKit

struct InstagramStoryPerson: Decodable, Identifiable { let id: String; let username: String; let avatar: String? }
struct InstagramThread: Decodable, Identifiable { let id: String; let title: String; let preview: String }
struct InstagramMessage: Decodable, Identifiable { let id: String; let text: String; let mine: Bool }
struct InstagramDataResult: Decodable {
    let posts: [InstagramPost]
    let stories: [InstagramStoryPerson]
    let threads: [InstagramThread]
    let messages: [InstagramMessage]
    let hasMore: Bool
    let error: String?
    let diagnostic: [String:String]
}

@MainActor
final class InstagramDataClient: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var posts: [InstagramPost] = []
    @Published private(set) var stories: [InstagramStoryPerson] = []
    @Published private(set) var threads: [InstagramThread] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = false
    @Published private(set) var error: String?
    private var webView: WKWebView?
    private var ready = false
    private var preparation: CheckedContinuation<Void, Error>?
    private var preparationTimeout: Task<Void, Never>?
    private var generation = 0
    private var retryAfter = Date.distantPast
    private var pendingTab: (tab: PorchModel.Tab, refresh: Bool)?
    private var activeTab: PorchModel.Tab?
    private var loadedTabs: Set<PorchModel.Tab> = []

    private func prepare() async throws {
        if ready { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.limitsNavigationsToAppBoundDomains = true
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        webView = view
        try await withCheckedThrowingContinuation { preparation = $0
            view.loadHTMLString("<!doctype html><html><head><title>Porch</title></head><body></body></html>", baseURL: URL(string:"https://www.instagram.com/"))
            preparationTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.preparation?.resume(throwing: ClientError.unavailable)
                self?.preparation = nil
                self?.webView?.stopLoading(); self?.webView?.navigationDelegate = nil; self?.webView = nil
            }
        }
    }

    func request(_ operation: String, identifier: String = "") async throws -> InstagramDataResult {
        guard ["feed","moreFeed","stories","story","inbox","thread"].contains(operation) else { throw ClientError.unavailable }
        guard Date() >= retryAfter else { throw ClientError.rateLimited }
        try await prepare()
        guard let webView, let path = Bundle.main.url(forResource:"instagram-data",withExtension:"js") else { throw ClientError.unavailable }
        let script = try String(contentsOf:path,encoding:.utf8)
        let value = try await webView.callAsyncJavaScript(script, arguments:["operation":operation,"identifier":identifier], in:nil,contentWorld:.defaultClient)
        guard let text = value as? String, let data = text.data(using:.utf8), data.count <= 1_000_000 else { throw ClientError.unavailable }
        let result = try JSONDecoder().decode(InstagramDataResult.self,from:data)
        if result.error == "rateLimited" { retryAfter = Date().addingTimeInterval(60) }
        return result
    }

    func load(_ tab: PorchModel.Tab, refresh: Bool = false) async {
        activeTab = tab
        if !refresh && loadedTabs.contains(tab) { error = nil; pendingTab = nil; return }
        guard !loading else { pendingTab = (tab, refresh); return }
        loading = true; error = nil
        let current = generation
        defer {
            if current == generation {
                loading = false
                if let next = pendingTab { pendingTab = nil; Task { await self.load(next.tab, refresh: next.refresh) } }
            }
        }
        do {
            let operation = tab == .stories ? "stories" : tab == .messages ? "inbox" : "feed"
            let result = try await request(operation)
            guard current == generation else { return }
            if activeTab == tab { error = result.error }
            if result.error == nil { loadedTabs.insert(tab) }
            switch tab {
            case .stories: stories = result.stories
            case .messages: threads = result.threads
            default: posts = result.posts; hasMore = result.hasMore
            }
        } catch ClientError.rateLimited { if current == generation && activeTab == tab { self.error = "rateLimited" } }
        catch { if current == generation && activeTab == tab { self.error = "unavailable" } }
    }

    func morePosts() async {
        guard !loading, hasMore else { return }
        loading = true; error = nil
        let current = generation
        defer {
            if current == generation {
                loading = false
                if let next = pendingTab { pendingTab = nil; Task { await self.load(next.tab, refresh: next.refresh) } }
            }
        }
        do {
            let result = try await request("moreFeed")
            guard current == generation else { return }
            if activeTab == .feed { error = result.error }
            hasMore = result.hasMore
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf:result.posts.filter { !existing.contains($0.id) })
        } catch ClientError.rateLimited { if current == generation && activeTab == .feed { self.error = "rateLimited" } }
        catch { if current == generation && activeTab == .feed { self.error = "unavailable" } }
    }

    func close() {
        generation += 1
        preparationTimeout?.cancel(); preparationTimeout = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil; ready = false
        preparation?.resume(throwing:ClientError.unavailable); preparation = nil
        posts = []; stories = []; threads = []; loading = false; error = nil; pendingTab = nil; hasMore = false; loadedTabs = []; activeTab = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        preparationTimeout?.cancel(); ready = true; preparation?.resume(); preparation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { preparationFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { preparationFailed(error) }
    private func preparationFailed(_ error: Error) {
        preparationTimeout?.cancel(); preparation?.resume(throwing:error); preparation = nil; ready = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { close(); error = "unavailable" }
    enum ClientError: Error { case unavailable, rateLimited }
}
