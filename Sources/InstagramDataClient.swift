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
struct SendAttempt: Codable, Equatable { let context: String; let started: Date; var traceID: String? = nil; var action: DiagnosticAction? = nil }

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
    @Published private(set) var lastFeedBatch: FeedBatch?
    private(set) var feedRetryCount = 10
    @Published private var loadingTabs: Set<PorchModel.Tab> = []
    @Published private var tabErrors: [PorchModel.Tab:String] = [:]
    @Published private var activeTab: PorchModel.Tab = .feed
    @Published private(set) var drafts: [String:String] = [:]
    @Published private(set) var pendingSends: [String:SendAttempt] = [:]
    @Published private(set) var sendingThreads: Set<String> = []
    @Published private(set) var diagnostic = "No request made."
    @Published private(set) var lastSendDiagnostic: String?
    private let transport: any InstagramTransport
    private let defaults: UserDefaults
    private let now: () -> Date
    private let diagnostics: DiagnosticsLog
    private var generation = 0
    private var retryAfter = Date.distantPast
    private var loadedTabs: Set<PorchModel.Tab> = []
    private var acceptedThreads: Set<String> = []
    private var pendingFeed: [InstagramPost] = []
    private var feedHasMore = false
    private var feedTruncated = false
    private var feedBatchTask: Task<Void, Never>?
    static let feedSessionLimit = 200
    struct FeedBatch { let requested: Int; let added: Int }
    var feedBatchOptions: [Int] {
        let available = min(Self.feedSessionLimit - posts.count, feedHasMore ? 20 : pendingFeed.count)
        return Array(Set([5, 10, 20].map { min($0, available) })).filter { $0 > 0 }.sorted()
    }
    // In-memory identities distinguish the submitted snapshot from later edits,
    // even when the user rewrites the same text. Neither map enters the journal.
    private var draftVersions: [String:UUID] = [:]
    private var submittedDraftVersions: [String:UUID] = [:]
    private let journalKey = "porch.pending-sends.v1"
    var error: String? { tabErrors[activeTab] }
    var loading: Bool { loadingTabs.contains(activeTab) }
    var hasLoadedCurrentTab: Bool { loadedTabs.contains(activeTab) }

    init(transport: (any InstagramTransport)? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
        self.transport = transport ?? WebKitInstagramTransport(diagnostics: diagnostics)
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: journalKey), let saved = try? JSONDecoder().decode([String:SendAttempt].self, from: data) { pendingSends = saved }
        for (thread, attempt) in pendingSends {
            diagnostics.record(.sendRestored, sendFields(thread, attempt).merging(["reason":"journal_restored"]) { _, b in b })
        }
    }
    func request(_ operation: String, identifier: String = "", feedCount: Int = 10) async throws -> InstagramDataResult {
        guard ["feed","moreFeed","stories","story","inbox","moreInbox","thread","olderMessages"].contains(operation) else { throw ClientError.unavailable }
        return try await execute(operation, identifier: identifier, feedCount: feedCount)
    }
    private func execute(_ operation: String, identifier: String = "", text: String = "", context: String = "", feedCount: Int = 10) async throws -> InstagramDataResult {
        guard now() >= retryAfter else { throw ClientError.rateLimited }
        let epoch = generation
        let result: InstagramDataResult
        do { result = try await transport.execute(operation, identifier: identifier, text: text, context: context, feedCount: feedCount) }
        catch {
            if epoch == generation {
                diagnostic = "View: \(operation)\nHTTP: none\nResult: \(Self.code(error))"
                if operation == "sendText" { lastSendDiagnostic = diagnostic }
            }
            throw error
        }
        guard epoch == generation else { throw CancellationError() }
        if result.error == "signIn" { tabErrors[activeTab] = "signIn" }
        if result.error == "rateLimited" { retryAfter = now().addingTimeInterval(Double(max(60, result.retryAfterSeconds ?? 60))) }
        let http = result.diagnostic["http"].flatMap(Int.init).map(String.init) ?? "none"
        let code = Self.knownError(result.error) ?? "none"
        let safeReasons = ["login_required", "user_has_logged_out", "challenge_required", "checkpoint_required", "two_factor_required",
                           "feedback_required", "sentry_block", "rate_limit_error", "unclassified", "invalid_response",
                           "missing_receipt", "receipt_mismatch"]
        let reason = result.diagnostic["reason"].flatMap { safeReasons.contains($0) ? $0 : nil } ?? "none"
        diagnostic = "View: \(operation)\nHTTP: \(http)\nResult: \(code)\nReason: \(reason)"
        if operation == "sendText" { lastSendDiagnostic = diagnostic }
        if operation == "inbox", result.error == nil { acceptedThreads = Set(result.threads.map(\.id)) }
        if operation == "moreInbox", result.error == nil { acceptedThreads.formUnion(result.threads.map(\.id)) }
        if (operation == "thread" || operation == "olderMessages"), result.error == nil, let attempt = pendingSends[identifier],
           result.messages.contains(where: { $0.mine && $0.context == attempt.context }) {
            diagnostics.record(.sendReconciled, sendFields(identifier, attempt))
            acknowledgeDraft(identifier)
            resolveSend(identifier, reason:"matching_context")
        }
        return result
    }
    func load(_ tab: PorchModel.Tab, refresh: Bool = false) async {
        activeTab = tab
        diagnostics.record(.tabLoad, ["view":tab.rawValue,"refresh":String(refresh),"generation":String(generation)])
        guard (refresh || !loadedTabs.contains(tab)), !loadingTabs.contains(tab) else {
            diagnostics.record(.tabCached,["view":tab.rawValue]); return
        }
        loadingTabs.insert(tab); tabErrors[tab] = nil
        let epoch = generation
        defer { if epoch == generation { loadingTabs.remove(tab) } }
        do {
            // Reserve the refresh first, then let the complete batch (including its
            // buffer update) finish before replacing the adapter's cursor.
            if tab == .feed { await feedBatchTask?.value }
            guard epoch == generation, !Task.isCancelled else { return }
            let result = try await request(tab == .stories ? "stories" : tab == .messages ? "inbox" : "feed")
            guard epoch == generation else { return }
            guard result.error == nil else { tabErrors[tab] = Self.knownError(result.error); return }
            loadedTabs.insert(tab)
            switch tab {
            case .stories: stories = result.stories
            case .messages: threads = result.threads; inboxHasMore = result.hasMore; inboxMoreError = nil
            case .feed:
                posts = []; pendingFeed = []; feedTruncated = false; lastFeedBatch = nil; feedRetryCount = 10
                acceptFeedPage(result)
                revealFeedPosts(10)
                moreError = nil
            }
        } catch { if epoch == generation { tabErrors[tab] = Self.code(error) } }
    }
    func morePosts(count: Int = 10) async {
        guard (1...20).contains(count), !moreLoading, !loadingTabs.contains(.feed), hasMore else { return }
        moreLoading = true; moreError = nil
        let epoch = generation
        let task = Task { await self.appendFeedBatch(count: count, epoch: epoch) }
        feedBatchTask = task
        await task.value
        if epoch == generation { moreLoading = false; feedBatchTask = nil }
    }
    private func appendFeedBatch(count: Int, epoch: Int) async {
        guard epoch == generation, !Task.isCancelled else { return }
        let amount = min(count, Self.feedSessionLimit - posts.count)
        feedRetryCount = amount
        lastFeedBatch = nil
        do {
            if pendingFeed.count < amount && feedHasMore {
                // At most one request. A short or duplicate-only page is a pause,
                // never a reason to chase more pages automatically.
                let result = try await request("moreFeed", feedCount: amount - pendingFeed.count)
                guard epoch == generation, !Task.isCancelled else { return }
                if let error = result.error { moreError = Self.knownError(error); return }
                acceptFeedPage(result)
            }
        } catch { if epoch == generation { moreError = Self.code(error) }; return }
        guard epoch == generation, !Task.isCancelled else { return }
        let before = posts.count
        revealFeedPosts(amount)
        lastFeedBatch = FeedBatch(requested: amount, added: posts.count - before)
    }
    private func acceptFeedPage(_ result: InstagramDataResult) {
        var existing = Set((posts + pendingFeed).map(\.id))
        let additions = result.posts.filter { existing.insert($0.id).inserted }
        let room = max(0, Self.feedSessionLimit - posts.count - pendingFeed.count)
        pendingFeed.append(contentsOf: additions.prefix(room))
        // Only the explicit, visible session boundary may truncate a page. All
        // overflow within that boundary stays in memory for later choices.
        feedTruncated = feedTruncated || additions.count > room
        feedHasMore = result.hasMore
    }
    private func revealFeedPosts(_ count: Int) {
        let amount = min(count, pendingFeed.count)
        posts.append(contentsOf: pendingFeed.prefix(amount))
        pendingFeed.removeFirst(amount)
        reachedSessionLimit = posts.count >= Self.feedSessionLimit && (feedHasMore || feedTruncated)
        hasMore = posts.count < Self.feedSessionLimit && (!pendingFeed.isEmpty || feedHasMore)
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
    func captureAction() -> DiagnosticAction? { diagnostics.actionContext }
    func sendText(_ text: String, to thread: String, action: DiagnosticAction? = nil) async -> String? {
        var fields = sendFields(thread, pendingSends[thread]); fields["message_utf16"] = String(text.utf16.count)
        fields.merge(action?.fields ?? [:]) { _, explicit in explicit }
        let invalid = !acceptedThreads.contains(thread) ? "invalid_recipient" : text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "empty_message" : text.utf16.count > 1000 ? "message_too_long" : nil
        if let invalid { fields["reason"] = invalid; diagnostics.record(.sendBlocked,fields); return "invalidMessage" }
        guard pendingSends[thread] == nil, !sendingThreads.contains(thread) else {
            fields["reason"] = sendingThreads.contains(thread) ? "in_flight" : "pending_send"
            diagnostics.record(.sendBlocked,fields); return "sendUnconfirmed"
        }
        guard now() >= retryAfter else { fields["reason"] = "cooldown"; diagnostics.record(.sendBlocked,fields); return "rateLimited" }
        let attempt = SendAttempt(context: String(UInt64.random(in: 1_000_000_000_000_000_000...9_000_000_000_000_000_000)), started: now(), traceID: UUID().uuidString, action: action ?? diagnostics.actionContext)
        #if DEBUG
        (transport as? BlindUITransport)?.associate(attempt)
        #endif
        if drafts[thread] == text { submittedDraftVersions[thread] = draftVersions[thread] }
        else { submittedDraftVersions[thread] = nil }
        pendingSends[thread] = attempt; saveJournal()
        sendingThreads.insert(thread)
        fields = sendFields(thread, attempt); fields["message_utf16"] = String(text.utf16.count)
        diagnostics.record(.sendPrepared,fields)
        let epoch = generation
        defer { if epoch == generation { sendingThreads.remove(thread) } }
        do {
            await diagnostics.flush()
            guard epoch == generation else { fields["reason"] = "generation_changed"; diagnostics.record(.sendUnconfirmed,fields); return "sendUnconfirmed" }
            diagnostics.record(.sendDispatched,fields)
            let result = try await execute("sendText", identifier: thread, text: text, context: attempt.context)
            guard epoch == generation else { fields["reason"] = "generation_changed"; diagnostics.record(.sendUnconfirmed,fields); return "sendUnconfirmed" }
            fields.merge(result.diagnostic) { _, b in b }
            if result.error == nil, let id = result.sentItemID, !id.isEmpty {
                diagnostics.record(.sendReceipt,fields)
                acknowledgeDraft(thread)
                resolveSend(thread, reason:"server_receipt")
                return nil
            }
            let failure = Self.knownError(result.error) ?? "sendUnconfirmed"
            fields["result"] = failure
            if ["signIn","rateLimited","actionBlocked","invalidMessage","sendRejected"].contains(failure) {
                diagnostics.record(.sendRefused,fields); resolveSend(thread, reason:"explicit_refusal")
            } else { diagnostics.record(.sendUnconfirmed,fields) }
            return failure
        } catch {
            fields.merge(DiagnosticsLog.errorFields(error)) { _, b in b }
            fields["result"] = "sendUnconfirmed"
            diagnostics.record(.sendUnconfirmed,fields); return "sendUnconfirmed"
        }
    }
    private func sendFields(_ thread: String, _ attempt: SendAttempt?) -> [String:String] {
        var fields = ["operation":"sendText","thread_ref":diagnostics.reference("identifier:"+thread),"pending_count":String(pendingSends.count),"generation":String(generation)]
        if let attempt {
            fields["context_ref"] = diagnostics.reference("context:"+attempt.context)
            if let trace = attempt.traceID { fields["attempt_id"] = trace }
            fields.merge(attempt.action?.fields ?? [:]) { _, explicit in explicit }
        }
        return fields
    }
    func keepDraft(_ text: String, for thread: String) {
        let value = text.isEmpty ? nil : String(text.prefix(4000))
        guard drafts[thread] != value else { return }
        draftVersions[thread] = UUID()
        drafts[thread] = value
    }
    private func acknowledgeDraft(_ thread: String) {
        if let submitted = submittedDraftVersions[thread], submitted == draftVersions[thread] {
            keepDraft("", for: thread)
        } else if drafts[thread] != nil {
            diagnostics.record(.viewState, sendFields(thread, pendingSends[thread]).merging(
                ["view": "Conversation", "state": "draft_preserved"]) { _, value in value })
        }
    }
    func resolveSend(_ thread: String, reason: String = "user_checked") {
        diagnostics.record(.sendWarningCleared,sendFields(thread,pendingSends[thread]).merging(["reason":reason]) { _, b in b })
        pendingSends[thread] = nil; submittedDraftVersions[thread] = nil; saveJournal()
    }
    private func saveJournal() { defaults.set(try? JSONEncoder().encode(pendingSends), forKey: journalKey) }
    func clearJournal() { pendingSends = [:]; submittedDraftVersions = [:]; lastSendDiagnostic = nil; defaults.removeObject(forKey: journalKey) }
    func close() {
        diagnostics.record(.sessionClosed,["pending_count":String(pendingSends.count),"generation":String(generation)])
        generation += 1; transport.close()
        feedBatchTask?.cancel(); feedBatchTask = nil
        pendingFeed = []; feedHasMore = false; feedTruncated = false; lastFeedBatch = nil; feedRetryCount = 10
        posts = []; stories = []; threads = []; drafts = [:]; hasMore = false; moreLoading = false; moreError = nil
        draftVersions = [:]; submittedDraftVersions = [:]
        inboxHasMore = false; inboxLoadingMore = false; inboxMoreError = nil
        loadingTabs = []; tabErrors = [:]; loadedTabs = []; acceptedThreads = []; sendingThreads = []; reachedSessionLimit = false
    }
    static func knownError(_ value: String?) -> String? {
        guard let value else { return nil }
        return ["offline","timedOut","signIn","rateLimited","actionBlocked","unsupported","unavailable","invalidMessage","sendRejected","sendUnconfirmed"].contains(value) ? value : "unavailable"
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
