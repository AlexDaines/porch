import SwiftUI

struct InstagramStoryPerson: Decodable, Identifiable { let id: String; let username: String; let avatar: String? }
struct InstagramThread: Decodable, Identifiable { let id: String; let title: String; let preview: String }
struct InstagramMessage: Decodable, Identifiable {
    let id: String
    let text: String
    let mine: Bool
    var context: String? = nil
    var sender: String? = nil
}
struct InstagramDataResult: Decodable {
    var posts: [InstagramPost] = []
    var stories: [InstagramStoryPerson] = []
    var threads: [InstagramThread] = []
    var messages: [InstagramMessage] = []
    var hasMore = false
    var error: String? = nil
    var diagnostic: [String:String] = [:]
    var retryAfterSeconds: Int? = nil
    var sentItemID: String? = nil
}

// The journal contains identifiers only, never message bodies or credentials. It survives
// an app exit between request dispatch and acknowledgement, when resending could duplicate a DM.
struct SendAttempt: Codable, Equatable { let context: String; let started: Date }

@MainActor
final class InstagramDataClient: ObservableObject {
    @Published private(set) var posts: [InstagramPost] = []
    @Published private(set) var stories: [InstagramStoryPerson] = []
    @Published private(set) var threads: [InstagramThread] = []
    @Published private(set) var hasMore = false
    @Published private(set) var moreLoading = false
    @Published private(set) var inboxHasMore = false
    @Published private(set) var inboxLoadingMore = false
    @Published private(set) var inboxMoreError: String?
    @Published private(set) var moreError: String?
    @Published private(set) var reachedSessionLimit = false
    @Published private var loadingTabs: Set<PorchModel.Tab> = []
    @Published private var tabErrors: [PorchModel.Tab:String] = [:]
    @Published private var activeTab: PorchModel.Tab = .feed
    @Published private(set) var drafts: [String:String] = [:]
    @Published private(set) var pendingSends: [String:SendAttempt] = [:]
    @Published private(set) var sendingThreads: Set<String> = []
    @Published private(set) var diagnostic = "No request made."
    private let transport: any InstagramTransport
    private let defaults: UserDefaults
    private let now: () -> Date
    private var generation = 0
    private var retryAfter = Date.distantPast
    private var loadedTabs: Set<PorchModel.Tab> = []
    private var acceptedThreads: Set<String> = []
    private let journalKey = "porch.pending-sends.v1"
    var error: String? { tabErrors[activeTab] }
    var loading: Bool { loadingTabs.contains(activeTab) }
    var hasLoadedCurrentTab: Bool { loadedTabs.contains(activeTab) }

    init(transport: (any InstagramTransport)? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.transport = transport ?? WebKitInstagramTransport()
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: journalKey), let saved = try? JSONDecoder().decode([String:SendAttempt].self, from: data) { pendingSends = saved }
    }
    func request(_ operation: String, identifier: String = "") async throws -> InstagramDataResult {
        guard ["feed","moreFeed","stories","story","inbox","moreInbox","thread","olderMessages"].contains(operation) else { throw ClientError.unavailable }
        return try await execute(operation, identifier: identifier)
    }
    private func execute(_ operation: String, identifier: String = "", text: String = "", context: String = "") async throws -> InstagramDataResult {
        guard now() >= retryAfter else { throw ClientError.rateLimited }
        let epoch = generation
        let result: InstagramDataResult
        do { result = try await transport.execute(operation, identifier: identifier, text: text, context: context) }
        catch {
            if epoch == generation { diagnostic = "View: \(operation)\nHTTP: none\nResult: \(Self.code(error))" }
            throw error
        }
        guard epoch == generation else { throw CancellationError() }
        if result.error == "signIn" { tabErrors[activeTab] = "signIn" }
        if result.error == "rateLimited" { retryAfter = now().addingTimeInterval(Double(max(60, min(result.retryAfterSeconds ?? 60, 86400)))) }
        let http = result.diagnostic["http"].flatMap(Int.init).map(String.init) ?? "none"
        let code = Self.knownError(result.error) ?? "none"
        diagnostic = "View: \(operation)\nHTTP: \(http)\nResult: \(code)"
        if operation == "inbox", result.error == nil { acceptedThreads = Set(result.threads.map(\.id)) }
        if operation == "moreInbox", result.error == nil { acceptedThreads.formUnion(result.threads.map(\.id)) }
        if (operation == "thread" || operation == "olderMessages"), result.error == nil, let attempt = pendingSends[identifier],
           result.messages.contains(where: { $0.mine && $0.context == attempt.context }) { resolveSend(identifier); drafts[identifier] = nil }
        return result
    }
    func load(_ tab: PorchModel.Tab, refresh: Bool = false) async {
        activeTab = tab
        guard (refresh || !loadedTabs.contains(tab)), !loadingTabs.contains(tab) else { return }
        loadingTabs.insert(tab); tabErrors[tab] = nil
        let epoch = generation
        defer { if epoch == generation { loadingTabs.remove(tab) } }
        do {
            let result = try await request(tab == .stories ? "stories" : tab == .messages ? "inbox" : "feed")
            guard epoch == generation else { return }
            guard result.error == nil else { tabErrors[tab] = Self.knownError(result.error); return }
            loadedTabs.insert(tab)
            switch tab {
            case .stories: stories = result.stories
            case .messages: threads = result.threads; inboxHasMore = result.hasMore; inboxMoreError = nil
            case .feed: posts = result.posts; hasMore = result.hasMore; moreError = nil; reachedSessionLimit = false
            }
        } catch { if epoch == generation { tabErrors[tab] = Self.code(error) } }
    }
    func morePosts() async {
        guard !moreLoading, !loadingTabs.contains(.feed), hasMore else { return }
        moreLoading = true; moreError = nil
        let epoch = generation
        defer { if epoch == generation { moreLoading = false } }
        do {
            let result = try await request("moreFeed")
            guard epoch == generation else { return }
            guard result.error == nil else { moreError = Self.knownError(result.error); return }
            var existing = Set(posts.map(\.id))
            let additions = result.posts.filter { existing.insert($0.id).inserted }
            let room = max(0, 200 - posts.count)
            posts.append(contentsOf: additions.prefix(room))
            reachedSessionLimit = posts.count >= 200 && result.hasMore
            hasMore = result.hasMore && !reachedSessionLimit
        } catch { if epoch == generation { moreError = Self.code(error) } }
    }
    func moreConversations() async {
        guard inboxHasMore, !inboxLoadingMore, !loadingTabs.contains(.messages) else { return }
        inboxLoadingMore = true; inboxMoreError = nil
        let epoch = generation
        defer { if epoch == generation { inboxLoadingMore = false } }
        do {
            let result = try await request("moreInbox")
            guard epoch == generation else { return }
            guard result.error == nil else { inboxMoreError = Self.knownError(result.error); return }
            var existing = Set(threads.map(\.id))
            threads.append(contentsOf:result.threads.filter { existing.insert($0.id).inserted }.prefix(max(0,200-threads.count)))
            inboxHasMore = result.hasMore && threads.count < 200
        } catch { if epoch == generation { inboxMoreError = Self.code(error) } }
    }
    func sendText(_ text: String, to thread: String) async -> String? {
        guard acceptedThreads.contains(thread), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              text.utf16.count <= 1000 else { return "invalidMessage" }
        guard pendingSends[thread] == nil, !sendingThreads.contains(thread) else { return "sendUnconfirmed" }
        guard now() >= retryAfter else { return "rateLimited" }
        let attempt = SendAttempt(context: String(UInt64.random(in: 1_000_000_000_000_000_000...9_000_000_000_000_000_000)), started: now())
        pendingSends[thread] = attempt; saveJournal()
        sendingThreads.insert(thread)
        let epoch = generation
        defer { if epoch == generation { sendingThreads.remove(thread) } }
        do {
            let result = try await execute("sendText", identifier: thread, text: text, context: attempt.context)
            guard epoch == generation else { return "sendUnconfirmed" }
            if result.error == nil, let id = result.sentItemID, !id.isEmpty {
                resolveSend(thread); drafts[thread] = nil
                return nil
            }
            let failure = Self.knownError(result.error) ?? "sendUnconfirmed"
            if ["signIn","rateLimited","invalidMessage","sendRejected"].contains(failure) { resolveSend(thread) }
            return failure
        } catch { return "sendUnconfirmed" }
    }
    func keepDraft(_ text: String, for thread: String) { drafts[thread] = text.isEmpty ? nil : String(text.prefix(4000)) }
    func resolveSend(_ thread: String) { pendingSends[thread] = nil; saveJournal() }
    private func saveJournal() { defaults.set(try? JSONEncoder().encode(pendingSends), forKey: journalKey) }
    func clearJournal() { pendingSends = [:]; defaults.removeObject(forKey: journalKey) }
    func close() {
        generation += 1; transport.close()
        posts = []; stories = []; threads = []; drafts = [:]; hasMore = false; moreLoading = false; moreError = nil
        inboxHasMore = false; inboxLoadingMore = false; inboxMoreError = nil
        loadingTabs = []; tabErrors = [:]; loadedTabs = []; acceptedThreads = []; sendingThreads = []; reachedSessionLimit = false
    }
    static func knownError(_ value: String?) -> String? {
        guard let value else { return nil }
        return ["offline","timedOut","signIn","rateLimited","unsupported","unavailable","invalidMessage","sendRejected","sendUnconfirmed"].contains(value) ? value : "unavailable"
    }
    static func code(_ error: Error) -> String {
        if case ClientError.rateLimited = error { return "rateLimited" }
        if let value = error as? URLError {
            if value.code == .notConnectedToInternet || value.code == .networkConnectionLost { return "offline" }
            if value.code == .timedOut { return "timedOut" }
        }
        return "unavailable"
    }
    enum ClientError: Error { case unavailable, rateLimited }
}
