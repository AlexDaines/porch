import XCTest
@testable import Porch

@MainActor
final class BlindUIFixtureTests: XCTestCase {
    private var directory: URL!
    private let body = "Thinking of you. How is your day?"
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private func makeStore(_ control: BlindUIControl = .accepted) -> (BlindUIStore, BlindUITransport, DiagnosticsLog, InstagramDataClient) {
        let runID = UUID().uuidString.lowercased()
        let store = BlindUIStore(runID: runID, directory: directory.appendingPathComponent(runID))
        let log = DiagnosticsLog(directory: directory.appendingPathComponent("diagnostics-" + runID))
        log.setActionContext(.init(runID: runID, actionID: UUID().uuidString, brokerSequence: 1))
        let transport = BlindUITransport(store: store, control: control, diagnostics: log)
        let name = "blind-ui-tests-" + runID
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (store, transport, log, InstagramDataClient(transport: transport, defaults: defaults, diagnostics: log))
    }
    func testAcceptedAndOpenedThreadRequiredByFixtureAndClient() async throws {
        let (store, _, _, client) = makeStore()
        let noInbox = await client.sendText(body, to: "8104")
        XCTAssertEqual(noInbox, "invalidMessage")
        await client.load(.messages)
        let unopened = await client.sendText(body, to: "8104")
        XCTAssertEqual(unopened, "invalidMessage")
        XCTAssertTrue(store.snapshot.writes.isEmpty)
        _ = try await client.request("thread", identifier: "8104")
        let accepted = await client.sendText(body, to: "8104")
        XCTAssertNil(accepted)
        XCTAssertEqual(store.snapshot.writes.map(\.recipient), ["fixture-mom-001"])
        XCTAssertEqual(store.snapshot.writes.map(\.text), [body])
        XCTAssertTrue(client.pendingSends.isEmpty)
    }
    func testEveryControlProducesIndependentOutcomeWithoutAutomaticRetry() async throws {
        for control in BlindUIControl.allCases {
            let (store, _, _, client) = makeStore(control)
            await client.load(.messages)
            _ = try await client.request("thread", identifier: "8104")
            let failure = await client.sendText(body, to: "8104")
            let writes = store.snapshot.writes
            switch control {
            case .accepted: XCTAssertNil(failure); XCTAssertEqual(writes.count, 1); XCTAssertEqual(writes.first?.text, body)
            case .rejected: XCTAssertEqual(failure, "actionBlocked"); XCTAssertTrue(writes.isEmpty)
            case .acceptedUnconfirmed:
                XCTAssertEqual(failure, "sendUnconfirmed"); XCTAssertEqual(writes.count, 1)
                let again = await client.sendText(body, to: "8104")
                XCTAssertEqual(again, "sendUnconfirmed"); XCTAssertEqual(store.snapshot.writes.count, 1)
                _ = try await client.request("thread", identifier: "8104")
                XCTAssertTrue(client.pendingSends.isEmpty)
                XCTAssertEqual(store.snapshot.writes.count, 1)
            case .wrongRecipient: XCTAssertNil(failure); XCTAssertEqual(writes.first?.recipient, "fixture-aunt-001")
            case .wrongText: XCTAssertNil(failure); XCTAssertNotEqual(writes.first?.text, body)
            case .duplicate: XCTAssertNil(failure); XCTAssertEqual(writes.count, 2); XCTAssertEqual(Set(writes.map(\.write_id)).count, 2)
            case .falseSuccess: XCTAssertNil(failure); XCTAssertTrue(writes.isEmpty)
            }
            XCTAssertFalse(store.snapshot.complete)
            XCTAssertTrue(store.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
            XCTAssertTrue(store.snapshot.complete)
        }
    }
    func testSinkExactSchemaFlushAndAttemptPrivacy() async throws {
        let (store, _, log, client) = makeStore()
        await client.load(.messages); _ = try await client.request("thread", identifier: "8104")
        _ = await client.sendText(body, to: "8104")
        await log.flush()
        let command = UUID().uuidString
        XCTAssertTrue(store.close(commandID: command, diagnosticsHealthy: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.directory.appendingPathComponent("sink.json"))) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "run_id", "complete", "writes"])
        let write = try XCTUnwrap((object["writes"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(write.keys), ["write_id", "recipient", "text"])
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.directory.appendingPathComponent("closed.json"))) as? [String: Any])
        XCTAssertEqual(Set(receipt.keys), ["schema", "run_id", "command_id", "complete"])
        XCTAssertEqual(receipt["command_id"] as? String, command)
        let attempts = try String(contentsOf: store.directory.appendingPathComponent("attempts.jsonl"), encoding: .utf8)
        XCTAssertFalse(attempts.contains(body)); XCTAssertTrue(attempts.contains("fixture-mom-001"))
        let export = try await log.export()
        let diagnostics = try String(contentsOf: export, encoding: .utf8)
        XCTAssertFalse(diagnostics.contains(body)); XCTAssertFalse(diagnostics.contains("fixture-mom-001")); XCTAssertFalse(diagnostics.contains("Mom"))
        for name in ["sink.json", "attempts.jsonl", "closed.json"] {
            let mode = try FileManager.default.attributesOfItem(atPath: store.directory.appendingPathComponent(name).path)[.posixPermissions] as? Int
            XCTAssertEqual(mode.map { $0 & 0o777 }, 0o600)
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
    }
    func testInterruptedRunPreservesWriteAndInvalidatesCompletion() throws {
        let run = UUID().uuidString
        let store = BlindUIStore(runID: run, directory: directory.appendingPathComponent("interrupted"))
        _ = store.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
        let resumed = BlindUIStore(runID: run, directory: store.directory)
        XCTAssertTrue(resumed.resumed); XCTAssertEqual(resumed.snapshot.writes, store.snapshot.writes)
        XCTAssertFalse(resumed.isHealthy)
        XCTAssertFalse(resumed.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
        XCTAssertFalse(resumed.snapshot.complete)
    }
    func testClosedRunRejectsLaterWriteAndRemainsImmutableOnRelaunch() {
        let store = BlindUIStore(runID: UUID().uuidString, directory: directory.appendingPathComponent("closed"))
        XCTAssertTrue(store.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
        let resumed = BlindUIStore(runID: store.runID, directory: store.directory)
        XCTAssertTrue(resumed.isClosed)
        let result = resumed.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
        XCTAssertEqual(result.error, "sendRejected"); XCTAssertTrue(resumed.snapshot.writes.isEmpty)
    }
    func testStorageFailureDoesNotChangeBusinessAcknowledgement() throws {
        let blocked = directory.appendingPathComponent("occupied")
        try Data("occupied".utf8).write(to: blocked)
        let store = BlindUIStore(runID: UUID().uuidString, directory: blocked)
        let result = store.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
        XCTAssertNil(result.error); XCTAssertEqual(result.writes.count, 1)
        XCTAssertFalse(store.isHealthy)
        XCTAssertFalse(store.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
        XCTAssertFalse(store.snapshot.complete)
    }
    func testBoundedStorageInvalidatesOverflowAndDiagnosticFailure() {
        let store = BlindUIStore(runID: UUID().uuidString, directory: directory.appendingPathComponent("bounded"), maximumRecords: 1)
        for _ in 0..<2 {
            let result = store.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
            XCTAssertNil(result.error); XCTAssertEqual(result.writes.count, 1)
        }
        XCTAssertEqual(store.snapshot.writes.count, 1); XCTAssertFalse(store.isHealthy)
        XCTAssertFalse(store.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
        let other = BlindUIStore(runID: UUID().uuidString, directory: directory.appendingPathComponent("diagnostic-failure"))
        XCTAssertFalse(other.close(commandID: UUID().uuidString, diagnosticsHealthy: false))
    }
    func testActionIsCapturedBeforeAsyncSendAndCorrelatesWithSink() async throws {
        let (store, _, log, client) = makeStore()
        await client.load(.messages); _ = try await client.request("thread", identifier: "8104")
        let original = try XCTUnwrap(client.captureAction())
        log.setActionContext(.init(runID: store.runID, actionID: UUID().uuidString, brokerSequence: 2))
        _ = await client.sendText(body, to: "8104", action: original)
        let events = await log.snapshot().entries.filter { [.sendPrepared, .sendDispatched, .sendReceipt].contains($0.event) }
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.fields["action_id"] == original.actionID && $0.fields["broker_sequence"] == "1" })
        let lines = try Data(contentsOf: store.directory.appendingPathComponent("attempts.jsonl")).split(separator: 10)
        let attempt = try JSONDecoder().decode(BlindUIAttempt.self, from: Data(try XCTUnwrap(lines.first)))
        XCTAssertEqual(attempt.action, original)
        XCTAssertEqual(attempt.attempt_id, events.first?.fields["attempt_id"])
        XCTAssertEqual(attempt.write_ids, store.snapshot.writes.map(\.write_id))
    }
    func testClosedViewAndActionSchemaRejectsContentAndInvalidIDs() {
        let uuid = UUID().uuidString
        let fields = DiagnosticsLog.sanitize(["view": "Conversation", "state": "sent", "run_id": uuid,
            "action_id": "PRIVATE_USER", "broker_sequence": "1", "text": body, "recipient": "Mom"])
        XCTAssertEqual(fields["run_id"], uuid); XCTAssertEqual(fields["state"], "sent")
        XCTAssertNil(fields["action_id"]); XCTAssertNil(fields["text"]); XCTAssertNil(fields["recipient"])
        XCTAssertNil(DiagnosticsLog.sanitize(["view": "Mom", "state": body])["view"])
    }
    func testLaunchConfigurationRequiresUUIDAndKnownControl() {
        let run = UUID().uuidString
        let args = ["--blind-ui-fixture", "--blind-ui-run-id", run]
        let config = BlindUILaunchConfiguration.parse(args, root: directory)
        XCTAssertEqual(config?.runID, run.lowercased())
        XCTAssertEqual(config?.directory.lastPathComponent, run.lowercased())
        XCTAssertNil(BlindUILaunchConfiguration.parse(["--blind-ui-fixture", "--blind-ui-run-id", "../private"], root: directory))
        XCTAssertNil(BlindUILaunchConfiguration.parse(args + ["--blind-ui-control", "live"], root: directory))
        XCTAssertNil(BlindUILaunchConfiguration.parse(args + ["--blind-ui-control"], root: directory))
        XCTAssertNil(BlindUILaunchConfiguration.parse(args + ["--blind-ui-run-id", run], root: directory))
    }
    func testMalformedActionStillAllowsIndependentInvalidClose() throws {
        let run = UUID().uuidString.lowercased()
        let path = directory.appendingPathComponent(run)
        try BlindUIStore.prepare(path)
        let command = UUID().uuidString
        try BlindUIStore.atomic(["schema": "blind-ui/control-v1", "run_id": run, "command": "close", "command_id": command], at: path.appendingPathComponent("control.json"))
        try BlindUIStore.atomic(["schema": "blind-ui/action-context-v1", "run_id": run, "action_id": "bad", "broker_sequence": 1] as [String: Any], at: path.appendingPathComponent("action-context.json"))
        let packet = BlindUIRuntime.readPacket(path)
        XCTAssertTrue(packet.malformed)
        XCTAssertNil(packet.action)
        XCTAssertEqual(packet.commandID, command)
        let action = UUID().uuidString
        try BlindUIStore.atomic(["schema": "blind-ui/action-context-v1", "run_id": run, "action_id": action, "broker_sequence": 2] as [String: Any], at: path.appendingPathComponent("action-context.json"))
        let valid = BlindUIRuntime.readPacket(path)
        XCTAssertFalse(valid.malformed)
        XCTAssertEqual(valid.action?.actionID, action)
        XCTAssertEqual(valid.commandID, command)
    }
    func testCompleteReceiptRequiresActionCorrelationForEveryAttempt() {
        let store = BlindUIStore(runID: UUID().uuidString, directory: directory.appendingPathComponent("uncorrelated"))
        _ = store.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
        XCTAssertFalse(store.close(commandID: UUID().uuidString, diagnosticsHealthy: true))
        XCTAssertFalse(store.snapshot.complete)
    }
    func testCommitOverheadIsMeasuredWithDurableEvidence() {
        let store = BlindUIStore(runID: UUID().uuidString, directory: directory.appendingPathComponent("timing"))
        var times: [Double] = []
        for _ in 0..<32 {
            let started = ProcessInfo.processInfo.systemUptime
            _ = store.record(recipient: "fixture-mom-001", text: body, context: "1234567890123456789", attemptID: UUID().uuidString, action: nil, control: .accepted, allowed: true)
            times.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
        }
        XCTAssertTrue(store.isHealthy); XCTAssertEqual(store.snapshot.writes.count, 32)
        print("Blind UI durable commit timing: count=32 mean_ms=\(times.reduce(0,+)/32) max_ms=\(times.max() ?? 0)")
    }
}
