import Foundation
import CryptoKit

struct DiagnosticAction: Codable, Equatable, Sendable {
    let runID: String
    var actionID: String? = nil
    var brokerSequence: Int? = nil
    var fields: [String: String] {
        var fields = ["run_id": runID]
        fields["action_id"] = actionID
        fields["broker_sequence"] = brokerSequence.map(String.init)
        return fields
    }
}

// Local engineering traces, not analytics. Every disk/export field passes the same
// closed schema. There is deliberately no API for logging an arbitrary message,
// URL, response body, Error description, cookie, username or conversation text.
final class DiagnosticsLog: @unchecked Sendable {
    enum Event: String, Codable {
        case appLaunch, lifecycle, network, memoryWarning, thermal
        case authStart, authHint, authVerify, authResult, authCancel, authSuppressed
        case authNavigation, authPageStarted, authPageFinished, authPageFailed, authCookiesChanged, authClear
        case requestQueued, requestStarted, requestContext, requestCompleted, requestFailed, requestCancelled
        case webPrepare, webReady, webFailed, webTerminated, transportClosed, adapterStage
        case tabLoad, tabCached, tabResult, pagination, sessionClosed
        case sendBlocked, sendPrepared, sendDispatched, sendReceipt, sendRefused, sendUnconfirmed
        case sendRestored, sendReconciled, sendWarningCleared
        case mediaStart, mediaReady, mediaPlaying, mediaFailed, mediaStopped, imageFailed
        case iosCrash, iosHang, iosCPUException, iosDiskException, iosLaunchDiagnostic
        case exportCreated, logsCleared
        case viewState, actionApplied, fixtureClosed
    }
    struct Entry: Codable {
        let schema: Int
        let timestamp: Date
        let uptime: Double
        let session: String
        let sequence: Int
        let event: Event
        let fields: [String: String]
    }
    struct Configuration {
        var segmentBytes = 2 * 1_024 * 1_024
        var segments = 10
        var retention: TimeInterval = 14 * 24 * 60 * 60
    }
    struct Snapshot {
        let entries: [Entry]
        let bytes: Int
        let writeFailures: Int
        let unreadableLines: Int
        let directoryAvailable: Bool
    }
    struct Report: Encodable {
        let schema = 1
        let created: Date
        let scope = "Local diagnostics. No credentials, conversation content, raw responses or identifying URLs."
        let retentionDays: Int
        let storageLimitBytes: Int
        let writeFailures: Int
        let unreadableLines: Int
        let directoryAvailable: Bool
        let environment: [String: String]
        let events: [Entry]
    }

    static let shared: DiagnosticsLog = {
        #if BLIND_UI_FIXTURE
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PorchBlindUI")
        let configuration = BlindUILaunchConfiguration.parse(ProcessInfo.processInfo.arguments, root: root)
        return DiagnosticsLog(directory: (configuration?.directory ?? root.appendingPathComponent("invalid")).appendingPathComponent("Diagnostics"))
        #else
        #if DEBUG
        let process = ProcessInfo.processInfo
        let fixture = process.arguments.contains("--uat-fixture") || process.arguments.contains("--sample") ||
            process.arguments.contains("--appearance-fixture") || process.environment["XCTestConfigurationFilePath"] != nil
        let name = fixture ? "PorchFixtureDiagnostics" : "PorchDiagnostics"
        #else
        let name = "PorchDiagnostics"
        #endif
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiagnosticsLog(directory: root.appendingPathComponent(name))
        #endif
    }()

    private let directory: URL
    private let config: Configuration
    private let queue = DispatchQueue(label: "dev.alex.porch.diagnostics", qos: .utility)
    private let key: SymmetricKey
    private let session = UUID().uuidString
    private let now: @Sendable () -> Date
    private var sequence = 0
    private var activeFile: URL?
    private var activeBytes = 0
    private var writeFailures = 0
    private var recent: [Entry] = []
    private var directoryAvailable = false
    private let actionLock = NSLock()
    private var currentAction: DiagnosticAction?
    var actionContext: DiagnosticAction? { actionLock.withLock { currentAction } }
    func setActionContext(_ action: DiagnosticAction?) { actionLock.withLock { currentAction = action } }

    init(directory: URL, configuration: Configuration = .init(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.config = configuration
        self.now = now
        let keyURL = directory.appendingPathComponent("redaction.key")
        var material = Data()
        do {
            try Self.prepareDirectory(directory)
            if let saved = try? Data(contentsOf: keyURL), saved.count == 32 { material = saved }
            else {
                material = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                try material.write(to: keyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                try Self.protect(keyURL)
            }
            directoryAvailable = true
        } catch { writeFailures = 1 }
        self.key = material.count == 32 ? SymmetricKey(data: material) : SymmetricKey(size: .bits256)
        queue.sync { prune() }
    }

    // Stable only within this installation; the key never enters an export or a
    // network request. IDs in logs can be correlated without revealing their values.
    func reference(_ value: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key).map { String(format: "%02x", $0) }.joined()
    }
    var adapterDiagnosticKey: String { key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() } }

    func record(_ event: Event, _ fields: [String: String] = [:]) {
        let contextual = (actionContext?.fields ?? [:]).merging(fields) { _, explicit in explicit }
        let safe = Self.sanitize(contextual)
        let date = now()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            sequence += 1
            let entry = Entry(schema: 1, timestamp: date, uptime: uptime, session: session,
                              sequence: sequence, event: event, fields: safe)
            append(entry)
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    func snapshot() async -> Snapshot {
        await withCheckedContinuation { continuation in queue.async { [self] in continuation.resume(returning: readSnapshot()) } }
    }
    func export() async throws -> URL {
        record(.exportCreated)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let snapshot = readSnapshot()
                    let report = Report(created: now(), retentionDays: Int(config.retention / 86_400),
                        storageLimitBytes: config.segmentBytes * config.segments,
                        writeFailures: snapshot.writeFailures, unreadableLines: snapshot.unreadableLines,
                        directoryAvailable: snapshot.directoryAvailable, environment: Self.environment(), events: snapshot.entries)
                    let destination = directory.appendingPathComponent("Exports", isDirectory: true)
                    try Self.prepareDirectory(destination)
                    for file in (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? [] {
                        try FileManager.default.removeItem(at: file)
                    }
                    let path = destination.appendingPathComponent("Porch-diagnostics.json")
                    let encoder = Self.encoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(report).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    try Self.protect(path)
                    continuation.resume(returning: path)
                } catch { writeFailures += 1; continuation.resume(throwing: error) }
            }
        }
    }
    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    for file in files() { try FileManager.default.removeItem(at: file) }
                    let exports = directory.appendingPathComponent("Exports")
                    if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
                    recent = []; activeFile = nil; activeBytes = 0
                } catch { writeFailures += 1; continuation.resume(throwing: error); return }
                continuation.resume()
            }
        }
        record(.logsCleared)
        await flush()
    }

    private func append(_ entry: Entry) {
        do {
            var data = try Self.encoder().encode(entry); data.append(0x0a)
            guard data.count <= config.segmentBytes else { writeFailures += 1; return }
            if activeFile == nil || activeBytes + data.count > config.segmentBytes {
                try Self.prepareDirectory(directory)
                let file = directory.appendingPathComponent("trace-\(UUID().uuidString).jsonl")
                try Data().write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                try Self.protect(file)
                activeFile = file; activeBytes = 0; directoryAvailable = true
            }
            guard let file = activeFile else { return }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
            activeBytes += data.count
            prune()
        } catch {
            writeFailures += 1
            recent.append(entry)
            if recent.count > 512 { recent.removeFirst(recent.count - 512) }
        }
    }
    private func files() -> [URL] {
        let values = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        return values.filter { $0.lastPathComponent.hasPrefix("trace-") && $0.pathExtension == "jsonl" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
        }
    }
    private func prune() {
        let all = files()
        for (index, file) in all.enumerated() {
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if index < all.count - config.segments || date < now().addingTimeInterval(-config.retention) {
                do {
                    try FileManager.default.removeItem(at: file)
                    if file == activeFile { activeFile = nil; activeBytes = 0 }
                } catch { writeFailures += 1 }
            }
        }
        let export = directory.appendingPathComponent("Exports/Porch-diagnostics.json")
        if let date = try? export.resourceValues(forKeys: [.creationDateKey]).creationDate,
           date < now().addingTimeInterval(-config.retention) {
            do { try FileManager.default.removeItem(at: export) } catch { writeFailures += 1 }
        }
    }
    private func readSnapshot() -> Snapshot {
        prune()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        var entries: [Entry] = [], bytes = 0, unreadable = 0
        for file in files() {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= config.segmentBytes else { unreadable += 1; continue }
            guard let data = try? Data(contentsOf: file) else { unreadable += 1; continue }
            bytes += data.count
            for line in data.split(separator: 0x0a) {
                guard line.count <= 32_768, let entry = try? decoder.decode(Entry.self, from: Data(line)),
                      entry.schema == 1, UUID(uuidString: entry.session) != nil, entry.uptime.isFinite else { unreadable += 1; continue }
                guard entry.timestamp >= now().addingTimeInterval(-config.retention) else { continue }
                entries.append(Entry(schema: 1, timestamp: entry.timestamp, uptime: entry.uptime, session: entry.session,
                    sequence: entry.sequence, event: entry.event, fields: Self.sanitize(entry.fields)))
            }
        }
        var existing = Set(entries.map { $0.session + ":" + String($0.sequence) })
        recent.removeAll { $0.timestamp < now().addingTimeInterval(-config.retention) }
        for entry in recent where existing.insert(entry.session + ":" + String(entry.sequence)).inserted { entries.append(entry) }
        entries.sort { $0.timestamp == $1.timestamp ? $0.sequence < $1.sequence : $0.timestamp < $1.timestamp }
        return Snapshot(entries: entries, bytes: bytes, writeFailures: writeFailures, unreadableLines: unreadable, directoryAvailable: directoryAvailable)
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var target = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    static func errorFields(_ error: Error) -> [String: String] {
        let ns = error as NSError
        var fields = ["error_domain": errorDomains.contains(ns.domain) ? ns.domain : "other", "error_code": String(ns.code)]
        var underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        var chain: [String] = []
        while let next = underlying, chain.count < 4 {
            chain.append((errorDomains.contains(next.domain) ? next.domain : "other") + ":" + String(next.code))
            underlying = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if !chain.isEmpty { fields["error_chain"] = chain.joined(separator: ";") }
        for (key, field) in [("WKJavaScriptExceptionLineNumber", "js_line"), ("WKJavaScriptExceptionColumnNumber", "js_column")] {
            if let value = ns.userInfo[key] as? NSNumber { fields[field] = value.stringValue }
        }
        return sanitize(fields)
    }
    static func environment() -> [String: String] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var system = utsname(); uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #if targetEnvironment(simulator)
        let hardware = "simulator"
        #else
        let hardware = machine
        #endif
        return sanitize(["app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "os_version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)", "hardware": hardware])
    }
    private static let errorDomains: Set<String> = ["NSURLErrorDomain", "WKErrorDomain", "NSCocoaErrorDomain", "AVFoundationErrorDomain", "NSOSStatusErrorDomain", "NSPOSIXErrorDomain", "other"]
    static let operations: Set<String> = ["sessionHint", "session", "feed", "moreFeed", "stories", "story", "inbox", "moreInbox", "thread", "olderMessages", "sendText"]
    static let errors: Set<String> = ["none", "offline", "timedOut", "signIn", "rateLimited", "actionBlocked", "unsupported", "unavailable", "invalidMessage", "sendRejected", "sendUnconfirmed", "cancelled"]
    static let maximumFields = 96
    private static let numbers: Set<String> = ["broker_sequence", "adapter_revision", "transport_request_index", "since_previous_fetch_ms", "large_integer_count", "retry_after_seconds", "cookie_count", "http", "duration_ms", "queue_ms", "fetch_ms", "decode_ms", "prepare_ms", "bridge_ms", "response_bytes", "response_chars", "request_bytes", "queue_depth", "generation", "posts", "stories", "threads", "messages", "raw_count", "filtered_count", "message_utf16", "pending_count", "cursor_length", "error_code", "exception_type", "exception_code", "signal", "frame_count", "duration_seconds", "memory_bytes", "schema_unknown_keys", "discarded_field_count", "payload_count", "period_start", "period_end", "js_line", "js_column"]
    private static let booleans: Set<String> = ["secure_context", "ua_mobile", "ua_safari", "account_changed", "challenge_present", "two_factor_present", "feedback_present", "spam_flag", "session_cookie_present", "csrf_cookie_present", "viewer_cookie_present", "device_cookie_present", "machine_cookie_present", "automatic", "saved_session", "has_more", "refresh", "csrf_present", "viewer_present", "context_valid", "thread_allowed", "thread_opened", "receipt_present", "receipt_thread_matches", "receipt_context_matches", "low_power", "expensive", "constrained", "ipv4", "ipv6", "dns", "simulator", "muted", "frames_truncated"]
    private static let enums: [String: Set<String>] = [
        "operation": operations, "result": errors, "error_domain": errorDomains, "savedSession": ["present", "absent"],
        "phase": ["idle", "signingIn", "connected"], "mode": ["welcome", "sample", "instagram", "finished"],
        "view": ["Feed", "Stories", "Messages", "Settings", "Diagnostics", "welcome", "Conversation", "Story"],
        "state": ["active", "inactive", "background", "foreground", "terminated", "satisfied", "unsatisfied", "requiresConnection", "nominal", "fair", "serious", "critical", "unknown", "visible", "hidden", "loading", "ready", "error", "sending", "sent", "unconfirmed", "draft_valid", "draft_invalid"],
        "interface": ["wifi", "cellular", "wiredEthernet", "loopback", "other", "none"],
        "method": ["GET", "POST"], "origin": ["instagram_web", "instagram_mobile", "instagram_cdn", "facebook_cdn", "other"],
        "content_type": ["json", "html", "text", "other", "missing"],
        "stage": ["validation", "fetch_started", "http_received", "decoded", "completed", "queued", "preparing", "bridge", "schema", "receipt", "watchdog", "asset", "player"],
        "reason": ["none", "user_has_logged_out", "login_required", "challenge_required", "checkpoint_required", "two_factor_required", "feedback_required", "sentry_block", "rate_limit_error", "unclassified", "invalid_response", "missing_receipt", "receipt_mismatch", "pending_send", "in_flight", "invalid_recipient", "empty_message", "message_too_long", "invalid_context", "missing_csrf", "cooldown", "generation_changed", "no_saved_session", "verification_failed", "user_cancel", "user_checked", "matching_context", "server_receipt", "explicit_refusal", "journal_restored", "rate_limit", "automatic_paused", "already_checking", "wrong_phase", "timeout", "transport_error", "process_terminated", "not_playable", "external_navigation", "blocked_surface", "invalid_navigation"],
        "navigation": ["login", "challenge", "checkpoint", "two_factor", "one_tap", "direct", "home", "instagram_other", "external", "invalid"],
        "decision": ["allow", "cancel", "new_window"], "source": ["app", "fixture", "metrickit"],
        "fetch_error": ["TimeoutError", "AbortError", "TypeError", "other", "none"],
        "document_origin": ["instagram_web", "opaque", "other"], "location_origin": ["instagram_web", "opaque", "other"],
        "document_kind": ["instagram_home", "local", "other"], "referrer_kind": ["empty", "present"],
        "ua_family": ["ios_webkit", "other_webkit", "other"], "cookie_store": ["persistent", "ephemeral"],
        "claim_reset": ["new_transport", "account_change", "csrf_change", "none"],
        "claim_sent": ["bootstrap", "server"], "claim_received": ["absent", "accepted", "rejected"],
        "response_type": ["basic", "cors", "opaque", "opaqueredirect", "default", "error", "other"],
        "json_parse": ["ok", "invalid"], "server_status": ["ok", "fail", "missing", "other"],
        "reason_source": ["none", "message", "error_type", "payload_message", "payload_error_type", "structure"]
    ]
    private static let shapePaths: Set<String> = ["payload.error_type", "spam", "error", "error.code", "error.error_subcode", "status", "message", "error_type", "payload", "payload.item_id", "payload.thread_id", "payload.client_context", "payload.message", "challenge", "two_factor_info", "feedback_message", "feedback_title", "inbox", "inbox.threads", "thread", "thread.items", "feed_items", "tray", "reels", "reels_media", "pagination_source", "has_older", "oldest_cursor"]
    static func sanitize(_ input: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (field, value) in input.prefix(Self.maximumFields) {
            if field == "exception_code", value.count <= 20, Int64(value) != nil || UInt64(value) != nil {
                result[field] = value
            } else if numbers.contains(field), value.count <= 20, let number = Double(value), number.isFinite, abs(number) <= 1e15 {
                result[field] = value
            } else if booleans.contains(field), ["true", "false"].contains(value) { result[field] = value
            } else if let values = enums[field], values.contains(value) { result[field] = value
            } else if ["request_id", "transport_id", "attempt_id", "run_id", "action_id"].contains(field), UUID(uuidString: value) != nil { result[field] = value
            } else if ["thread_ref", "context_ref", "media_ref", "server_fingerprint"].contains(field), value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil { result[field] = value
            } else if ["app_version", "build", "os_version"].contains(field), value.range(of: "^[0-9.]{1,24}$", options: .regularExpression) != nil { result[field] = value
            } else if field == "hardware", value.range(of: "^(iPhone|iPad)[0-9]{1,3},[0-9]{1,3}$|^simulator$", options: .regularExpression) != nil { result[field] = value
            } else if field == "response_shape" {
                let parts = value.prefix(2_048).split(separator: ";").compactMap { part -> String? in
                    let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2, shapePaths.contains(pair[0]), ["null", "string", "number", "boolean", "object", "array"].contains(pair[1]) else { return nil }
                    return pair.joined(separator: "=")
                }
                if !parts.isEmpty { result[field] = parts.joined(separator: ";") }
            } else if field == "error_chain", value.count <= 256 {
                let chain = value.split(separator: ";").prefix(4).compactMap { part -> String? in
                    let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
                    guard pair.count == 2, errorDomains.contains(pair[0]), Int64(pair[1]) != nil else { return nil }
                    return pair.joined(separator: ":")
                }
                if !chain.isEmpty { result[field] = chain.joined(separator: ";") }
            } else if field == "frames", value.count <= 8_192 {
                let frames = value.split(separator: ",").filter { $0.range(of: "^[A-Fa-f0-9-]{36}@[0-9]{1,20}$", options: .regularExpression) != nil }
                if !frames.isEmpty { result[field] = frames.prefix(64).joined(separator: ",") }
            }
        }
        let dropped = input.count - result.count
        if dropped > 0 { result["discarded_field_count"] = String(dropped) }
        return result
    }
}
