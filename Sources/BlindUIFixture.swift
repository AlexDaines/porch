#if DEBUG
import Foundation
import SwiftUI
import Darwin

// This file contains synthetic study data only. Nothing here is included in Release.
struct BlindUILaunchConfiguration {
    let runID: String
    let control: BlindUIControl
    let directory: URL
    var defaultsName: String { "porch.blind-ui." + runID }
    static func parse(_ arguments: [String], root: URL) -> Self? {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count,
                  arguments.filter({ $0 == flag }).count == 1 else { return nil }
            return arguments[index + 1]
        }
        guard arguments.contains("--blind-ui-fixture"),
              let raw = value("--blind-ui-run-id"), let uuid = UUID(uuidString: raw) else { return nil }
        if arguments.contains("--blind-ui-control"), value("--blind-ui-control") == nil { return nil }
        let rawControl = value("--blind-ui-control") ?? "accepted"
        guard let control = BlindUIControl(rawValue: rawControl) else { return nil }
        // Canonical lowercase directories avoid two stores for the same UUID.
        let runID = uuid.uuidString.lowercased()
        return Self(runID: runID, control: control, directory: root.appendingPathComponent(runID, isDirectory: true))
    }
}

enum BlindUIControl: String, Codable, CaseIterable {
    case accepted, rejected, acceptedUnconfirmed = "accepted-unconfirmed"
    case wrongRecipient = "wrong-recipient", wrongText = "wrong-text", duplicate, falseSuccess = "false-success"
}

struct BlindUIWrite: Codable, Equatable {
    let write_id: String
    let recipient: String
    let text: String
}
struct BlindUISink: Codable {
    let schema: String
    let run_id: String
    var complete: Bool
    var writes: [BlindUIWrite]
}
struct BlindUIAttempt: Codable {
    let schema: String
    let run_id: String
    let attempt_id: String
    let context: String
    let action: DiagnosticAction?
    let recipient: String
    let text_utf16: Int
    let result: String
    let write_ids: [String]
}

// Business acceptance and evidence health are distinct. Disk failures never change
// the UI result; they permanently prevent a complete evidence receipt for this run.
// Synchronous serial commits ensure close cannot overtake an accepted fixture write.
final class BlindUIStore: @unchecked Sendable {
    let runID: String
    let directory: URL
    private let queue = DispatchQueue(label: "dev.alex.porch.blind-ui.store", qos: .utility)
    private var sink: BlindUISink
    private var attempts: [BlindUIAttempt] = []
    private var healthy = true
    private var closed = false
    private let maximumRecords: Int
    private(set) var resumed = false
    init(runID: String, directory: URL, maximumRecords: Int = 256) {
        self.runID = runID; self.directory = directory; self.maximumRecords = maximumRecords
        sink = .init(schema: "blind-ui/sink-v1", run_id: runID, complete: false, writes: [])
        do {
            try Self.prepare(directory)
            let path = directory.appendingPathComponent("sink.json")
            if FileManager.default.fileExists(atPath: path.path) {
                resumed = true
                let saved = try JSONDecoder().decode(BlindUISink.self, from: Self.read(path, limit: 2_097_152))
                guard saved.schema == "blind-ui/sink-v1", saved.run_id == runID,
                      saved.writes.count <= maximumRecords,
                      Set(saved.writes.map(\.write_id)).count == saved.writes.count else { throw CocoaError(.fileReadCorruptFile) }
                sink = saved; closed = saved.complete
                let journal = directory.appendingPathComponent("attempts.jsonl")
                if FileManager.default.fileExists(atPath: journal.path) {
                    let data = try Self.read(journal, limit: 1_048_576)
                    guard data.isEmpty || data.last == 10 else { throw CocoaError(.fileReadCorruptFile) }
                    attempts = try data.split(separator: 10).map { try JSONDecoder().decode(BlindUIAttempt.self, from: Data($0)) }
                    guard attempts.count <= maximumRecords,
                          attempts.allSatisfy({ $0.run_id == runID && $0.schema == "blind-ui/attempt-v1" }) else { throw CocoaError(.fileReadCorruptFile) }
                }
                let recorded = Set(attempts.flatMap(\.write_ids))
                guard recorded == Set(sink.writes.map(\.write_id)) else { throw CocoaError(.fileReadCorruptFile) }
                // A launch without recorder close is not proof of a lossless crash.
                // Preserve all evidence and the pending-send journal, but invalidate
                // the interrupted study even if the app can recover its conversation.
                if !saved.complete { healthy = false }
            } else {
                try Self.atomic(sink, at: path)
            }
        } catch { healthy = false }
    }
    var snapshot: BlindUISink { queue.sync { sink } }
    var isHealthy: Bool { queue.sync { healthy } }
    var isClosed: Bool { queue.sync { closed } }
    func invalidate() { queue.sync { healthy = false } }
    func record(recipient: String, text: String, context: String, attemptID: String,
                action: DiagnosticAction?, control: BlindUIControl, allowed: Bool) -> (writes: [BlindUIWrite], error: String?) {
        queue.sync {
            guard !closed else { return ([], "sendRejected") }
            let error: String? = !allowed ? "invalidMessage" : control == .rejected ? "actionBlocked" :
                control == .acceptedUnconfirmed ? "sendUnconfirmed" : nil
            var accepted: [BlindUIWrite] = []
            if allowed && control != .rejected && control != .falseSuccess {
                let target = control == .wrongRecipient ? "fixture-aunt-001" : recipient
                let body = control == .wrongText ? "See you soon." : text
                accepted = (0..<(control == .duplicate ? 2 : 1)).map { _ in
                    .init(write_id: UUID().uuidString.lowercased(), recipient: target, text: body)
                }
            }
            let attempt = BlindUIAttempt(schema: "blind-ui/attempt-v1", run_id: runID, attempt_id: attemptID,
                context: context, action: action, recipient: recipient, text_utf16: text.utf16.count,
                result: error ?? "accepted", write_ids: accepted.map(\.write_id))
            if attempts.count >= maximumRecords || sink.writes.count + accepted.count > maximumRecords {
                healthy = false // Continue business/UI behavior, never claim complete evidence.
            } else {
                attempts.append(attempt); sink.writes.append(contentsOf: accepted)
                do {
                    // Acceptance is recorded first; a crash between these writes leaves
                    // an incomplete sink and cannot be scored as a valid absence.
                    try Self.atomic(sink, at: directory.appendingPathComponent("sink.json"))
                    var data = try JSONEncoder().encode(attempt); data.append(10)
                    let path = directory.appendingPathComponent("attempts.jsonl")
                    if !FileManager.default.fileExists(atPath: path.path) {
                        guard FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                    }
                    let handle = try FileHandle(forWritingTo: path)
                    defer { try? handle.close() }
                    try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
                } catch { healthy = false }
            }
            return (accepted, error)
        }
    }
    func messages(for recipient: String) -> [InstagramMessage] {
        queue.sync {
            sink.writes.filter { $0.recipient == recipient }.map { write in
                .init(id: write.write_id, text: write.text, mine: true,
                      context: attempts.first(where: { $0.write_ids.contains(write.write_id) })?.context)
            }
        }
    }
    @discardableResult func close(commandID: String, diagnosticsHealthy: Bool) -> Bool {
        queue.sync {
            guard UUID(uuidString: commandID) != nil else { healthy = false; return false }
            closed = true
            let correlated = attempts.allSatisfy { attempt in
                guard let action = attempt.action, action.runID == runID,
                      let id = action.actionID, UUID(uuidString: id) != nil,
                      let sequence = action.brokerSequence, (1...100_000).contains(sequence) else { return false }
                return true
            }
            healthy = healthy && diagnosticsHealthy && correlated
            sink.complete = healthy
            do {
                try Self.atomic(sink, at: directory.appendingPathComponent("sink.json"))
                // The receipt also acknowledges an invalid close without disguising it.
                try Self.atomic(["schema": "blind-ui/closed-v1", "run_id": runID,
                    "command_id": commandID, "complete": sink.complete] as [String: Any],
                    at: directory.appendingPathComponent("closed.json"))
            } catch { healthy = false; sink.complete = false; return false }
            return healthy
        }
    }
    static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        var value = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try value.setResourceValues(flags)
    }
    static func read(_ url: URL, limit: Int = 4096) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    static func atomic<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try atomicData(encoder.encode(value), at: url)
    }
    static func atomic(_ value: [String: Any], at url: URL) throws {
        try atomicData(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), at: url)
    }
    private static func atomicData(_ data: Data, at url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }; try file.synchronize()
        let fd = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(.EIO) }; defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }
}

@MainActor
final class BlindUITransport: InstagramTransport {
    struct Person { let thread: String; let recipient: String; let name: String; let preview: String }
    static let people: [Person] = [
        .init(thread: "8101", recipient: "fixture-maya-001", name: "Maya", preview: "That place looks lovely."),
        .init(thread: "8102", recipient: "fixture-weekend-001", name: "Weekend plans", preview: "Saturday works for me."),
        .init(thread: "8103", recipient: "fixture-leo-001", name: "Leo", preview: "Just got back."),
        .init(thread: "8104", recipient: "fixture-mom-001", name: "Mom", preview: "The garden is looking good today."),
        .init(thread: "8105", recipient: "fixture-aunt-001", name: "Aunt Linda", preview: "Thanks for the photos."),
        .init(thread: "8106", recipient: "fixture-rides-001", name: "Moped rides", preview: "Coffee after the ride?")
    ]
    let store: BlindUIStore
    private let control: BlindUIControl
    private let diagnostics: DiagnosticsLog
    private var accepted = Set<String>()
    private var opened = Set<String>()
    private var attempts: [String: SendAttempt] = [:]
    var closing = false
    init(store: BlindUIStore, control: BlindUIControl = .accepted, diagnostics: DiagnosticsLog = .shared) {
        self.store = store; self.control = control; self.diagnostics = diagnostics
    }
    func associate(_ attempt: SendAttempt) { attempts[attempt.context] = attempt }
    func execute(_ operation: String, identifier: String, text: String, context: String, feedCount: Int = 10) async throws -> InstagramDataResult {
        guard !closing && !store.isClosed else { return .init(error: "unavailable") }
        let requestID = UUID().uuidString
        let attempt = attempts.removeValue(forKey: context)
        var fields = ["source": "fixture", "operation": operation, "request_id": requestID]
        if let attempt {
            fields.merge(attempt.action?.fields ?? [:]) { _, new in new }
            fields["attempt_id"] = attempt.traceID
        }
        if !identifier.isEmpty { fields["thread_ref"] = diagnostics.reference("identifier:" + identifier) }
        diagnostics.record(.requestStarted, fields)
        var result = InstagramDataResult()
        switch operation {
        case "feed": result.posts = Self.posts
        case "inbox":
            accepted = Set(Self.people.map(\.thread))
            result.threads = Self.people.map { .init(id: $0.thread, title: $0.name, preview: $0.preview) }
        case "thread", "olderMessages":
            guard accepted.contains(identifier), let person = Self.people.first(where: { $0.thread == identifier }) else { return .init(error: "invalidMessage") }
            opened.insert(identifier)
            if operation == "thread" {
                result.messages = [.init(id: "initial-" + identifier, text: person.preview, mine: false)] + store.messages(for: person.recipient)
            }
        case "sendText":
            let person = Self.people.first { $0.thread == identifier }
            let allowed = accepted.contains(identifier) && opened.contains(identifier) && person != nil &&
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 1000 &&
                context.range(of: "^[0-9]{19}$", options: .regularExpression) != nil
            let receipt = store.record(recipient: person?.recipient ?? "fixture-unknown", text: text, context: context,
                attemptID: attempt?.traceID ?? UUID().uuidString, action: attempt?.action ?? diagnostics.actionContext,
                control: control, allowed: allowed)
            result.error = receipt.error
            if receipt.error == nil { result.sentItemID = receipt.writes.first?.write_id ?? UUID().uuidString }
            fields["thread_allowed"] = String(accepted.contains(identifier)); fields["thread_opened"] = String(opened.contains(identifier))
        case "stories": result.stories = [.init(id: "8201", username: "maya", avatar: nil), .init(id: "8202", username: "leo", avatar: nil)]
        case "story": result.posts = Array(Self.posts.prefix(1))
        case "moreFeed", "moreInbox": break
        default: result.error = "unavailable"
        }
        fields["result"] = result.error ?? "none"
        diagnostics.record(.requestCompleted, fields)
        return result
    }
    func close() { accepted.removeAll(); opened.removeAll(); attempts.removeAll() }
    static var posts: [InstagramPost] { [
        .init(id: "8301", username: "maya", caption: "A quiet afternoon by the water.", timestamp: 1_789_000_000,
              media: [.init(url: "blind-ui://water", width: 900, height: 650, video: nil, isVideo: false, alt: "An illustration of the water and distant hills.")]),
        .init(id: "8302", username: "leo", caption: "Made it out before the rain.", timestamp: 1_788_900_000, media: [])
    ] }
}

// A local illustration occupies the normal photo surface. No remote image URL is
// ever handed to AsyncImage in the dedicated fixture target, even on bad config.
struct BlindUIPhoto: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xA3B8B6)))
            var hills = Path(); hills.move(to: .init(x: 0, y: size.height * 0.52))
            hills.addLines([.init(x: size.width * 0.3, y: size.height * 0.29), .init(x: size.width * 0.6, y: size.height * 0.5),
                .init(x: size.width * 0.82, y: size.height * 0.36), .init(x: size.width, y: size.height * 0.49),
                .init(x: size.width, y: size.height), .init(x: 0, y: size.height)])
            context.fill(hills, with: .color(Color(hex: 0x556C5C)))
            context.fill(Path(CGRect(x: 0, y: size.height * 0.58, width: size.width, height: size.height * 0.42)), with: .color(Color(hex: 0x667F81)))
        }.aspectRatio(900.0 / 650, contentMode: .fit)
    }
}
#endif
