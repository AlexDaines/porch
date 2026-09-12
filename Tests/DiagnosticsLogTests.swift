import XCTest
@testable import Porch

final class DiagnosticsLogTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("porch-log-tests-" + UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testRequestContextExportsCategoriesWithoutCookiesClaimsOrDeviceIdentifiers() async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: ".instagram.com", .path: "/", .name: "sessionid", .value: "PRIVATE_SESSION"]))
        let foreign = try XCTUnwrap(HTTPCookie(properties: [.domain: "foreign.example", .path: "/", .name: "ig_did", .value: "PRIVATE_DEVICE"]))
        let fields = WebKitInstagramTransport.cookieDiagnostics([cookie, foreign])
        XCTAssertEqual(fields["session_cookie_present"], "true")
        XCTAssertEqual(fields["device_cookie_present"], "false")
        XCTAssertEqual(fields["cookie_count"], "1")
        let log = DiagnosticsLog(directory: directory)
        log.record(.requestContext, fields.merging(["cookie_store": "persistent", "cookie": "PRIVATE_COOKIE"]) { _, new in new })
        log.record(.adapterStage, ["document_origin": "instagram_web", "location_origin": "opaque", "ua_family": "ios_webkit",
            "claim_sent": "server", "claim_received": "accepted", "large_integer_count": "2", "reason_source": "payload_error_type",
            "claim": "PRIVATE_CLAIM", "user_agent": "PRIVATE_AGENT", "document_url": "https://PRIVATE.example/", "response_shape": "spam=boolean;payload.error_type=string"])
        let export = try await log.export()
        let text = try String(contentsOf: export, encoding: .utf8)
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertTrue(text.contains("session_cookie_present"))
        XCTAssertTrue(text.contains("payload_error_type"))
        XCTAssertTrue(text.contains("ios_webkit"))
    }

    func testComposerFocusExportRetainsCorrelationAndExcludesPrivateInput() async throws {
        let log = DiagnosticsLog(directory: directory)
        let action = DiagnosticAction(runID: UUID().uuidString, actionID: UUID().uuidString, brokerSequence: 3)
        log.setActionContext(action)
        let states = ["composer_focus_requested", "composer_focused", "composer_blurred", "draft_preserved"]
        for state in states {
            log.record(.viewState, ["view": "Conversation", "state": state,
                "thread_ref": log.reference("PRIVATE_THREAD"), "text": "PRIVATE_DRAFT", "selection": "PRIVATE_SELECTION"])
        }
        log.record(.viewState, ["state": "composer_focused PRIVATE_DRAFT"])
        let entries = await log.snapshot().entries
        XCTAssertEqual(entries.prefix(states.count).compactMap { $0.fields["state"] }, states)
        XCTAssertTrue(entries.allSatisfy { $0.fields["action_id"] == action.actionID })
        XCTAssertNil(entries.last?.fields["state"], "Arbitrary focus-state strings must be rejected")
        let exported = try String(contentsOf: await log.export(), encoding: .utf8)
        XCTAssertFalse(exported.contains("PRIVATE"))
        XCTAssertTrue(exported.contains("composer_focused"))
    }

    func testDurableExportCorrelatesAcrossLaunchesWithoutPrivateValues() async throws {
        let first = DiagnosticsLog(directory: directory)
        let reference = first.reference("PRIVATE_THREAD")
        let request = UUID().uuidString
        first.record(.sendPrepared, ["request_id": request, "thread_ref": reference, "message_utf16": "8",
            "text": "PRIVATE_MESSAGE", "cookie": "PRIVATE_COOKIE", "reason": "PRIVATE_REASON",
            "response_shape": "message=string;PRIVATE_KEY=PRIVATE_VALUE;payload.item_id=string"])
        await first.flush()
        let restarted = DiagnosticsLog(directory: directory)
        XCTAssertEqual(restarted.reference("PRIVATE_THREAD"), reference)
        restarted.record(.sendRefused, ["request_id": request, "thread_ref": reference, "result": "actionBlocked", "http": "400"])
        let snapshot = await restarted.snapshot()
        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(Set(snapshot.entries.map(\.session)).count, 2)
        XCTAssertTrue(snapshot.entries.allSatisfy { $0.fields["request_id"] == request })
        let url = try await restarted.export()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertFalse(text.contains(restarted.adapterDiagnosticKey))
        XCTAssertTrue(text.contains(reference))
        XCTAssertTrue(text.contains("payload.item_id=string"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testRotationAndRetentionDoNotResurrectOldMemoryEntries() async throws {
        let config = DiagnosticsLog.Configuration(segmentBytes: 700, segments: 3, retention: 86_400)
        let log = DiagnosticsLog(directory: directory, configuration: config)
        for index in 0..<40 { log.record(.requestStarted, ["message_utf16": String(index)]) }
        let snapshot = await log.snapshot()
        XCTAssertLessThanOrEqual(snapshot.bytes, 2_100)
        XCTAssertLessThan(snapshot.entries.count, 40)
        XCTAssertEqual(snapshot.entries.last?.fields["message_utf16"], "39")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        XCTAssertLessThanOrEqual(files.count, 3)
        let exported = try await log.export()
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exported)) as? [String: Any])
        XCTAssertEqual((report["environment"] as? [String: String])?["build"], Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            "Build metadata must survive rotation of the appLaunch event")
        let future = Date().addingTimeInterval(2 * 86_400)
        let expired = DiagnosticsLog(directory: directory, configuration: config, now: { future })
        let empty = await expired.snapshot()
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.bytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
    }

    func testInterruptedAndTamperedEntriesAreBoundedAndSanitizedAgainAtExport() async throws {
        let log = DiagnosticsLog(directory: directory)
        log.record(.appLaunch)
        await log.flush()
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "jsonl" })
        let entry = DiagnosticsLog.Entry(schema: 1, timestamp: Date(), uptime: 1, session: UUID().uuidString,
            sequence: 1, event: .adapterStage, fields: ["operation": "sendText", "http": "400", "message": "PRIVATE_TAMPER", "error_domain": "PRIVATE_DOMAIN"])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        var data = try encoder.encode(entry); data.append(contentsOf: "\n{partial PRIVATE_TAIL".utf8)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close()
        let restarted = DiagnosticsLog(directory: directory)
        let snapshot = await restarted.snapshot()
        XCTAssertEqual(snapshot.unreadableLines, 1)
        XCTAssertEqual(snapshot.entries.count, 2)
        let exported = try await restarted.export()
        XCTAssertFalse(try String(contentsOf: exported, encoding: .utf8).contains("PRIVATE"))
        // Oversized damaged files are never loaded wholesale into memory.
        try Data(repeating: 0x61, count: 2 * 1_024 * 1_024 + 1).write(to: file)
        let oversized = await restarted.snapshot()
        XCTAssertEqual(oversized.unreadableLines, 1)
    }

    func testClearRemovesAllTraceSegmentsAndExistingExport() async throws {
        let log = DiagnosticsLog(directory: directory)
        log.record(.sendRefused, ["http": "400"])
        let export = try await log.export()
        try await log.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        let restarted = DiagnosticsLog(directory: directory)
        let snapshot = await restarted.snapshot()
        XCTAssertEqual(snapshot.entries.map(\.event), [.logsCleared])
    }

    func testUnavailableStorageIsVisibleAndDoesNotThrowFromRecording() async throws {
        try Data("occupied".utf8).write(to: directory)
        let log = DiagnosticsLog(directory: directory)
        log.record(.sendDispatched, ["operation": "sendText"])
        let snapshot = await log.snapshot()
        XCTAssertFalse(snapshot.directoryAvailable)
        XCTAssertGreaterThan(snapshot.writeFailures, 0)
        XCTAssertEqual(snapshot.entries.map(\.event), [.sendDispatched])
        do { _ = try await log.export(); XCTFail("An unavailable export must surface a failure") } catch { }
    }

    func testErrorAndMetricKitSchemasRejectExceptionTextAndPaths() throws {
        let error = NSError(domain: "PRIVATE_DOMAIN", code: -1009, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_MESSAGE", NSURLErrorFailingURLErrorKey: "https://private.example/token"])
        XCTAssertEqual(DiagnosticsLog.errorFields(error), ["error_domain": "other", "error_code": "-1009"])
        let uuid = UUID().uuidString
        let stack: [String: Any] = ["exceptionReason": "PRIVATE_EXCEPTION", "callStacks": [["threadName": "PRIVATE_THREAD", "callStackRootFrames": [["binaryUUID": uuid, "binaryName": "PRIVATE_PATH", "offsetIntoBinaryTextSegment": 42, "subFrames": [["binaryUUID": uuid, "offsetIntoBinaryTextSegment": 84]]]]]]]
        let fields = SystemDiagnostics.stackFields(try JSONSerialization.data(withJSONObject: stack))
        XCTAssertEqual(fields["frames"], "\(uuid)@42,\(uuid)@84")
        XCTAssertEqual(fields["frame_count"], "2")
        XCTAssertFalse(fields.description.contains("PRIVATE"))
        let bad = DiagnosticsLog.sanitize(["http": "400 PRIVATE", "request_id": "PRIVATE_ID", "frames": "PRIVATE_STACK", "thread_ref": "1234", "url": "PRIVATE_URL"])
        XCTAssertEqual(bad, ["discarded_field_count": "5"])
        let wrapped = NSError(domain: "WKErrorDomain", code: 5, userInfo: [NSUnderlyingErrorKey: error, "WKJavaScriptExceptionLineNumber": 18, "WKJavaScriptExceptionMessage": "PRIVATE_TEXT"])
        let safe = DiagnosticsLog.errorFields(wrapped)
        XCTAssertEqual(safe["error_chain"], "other:-1009")
        XCTAssertEqual(safe["js_line"], "18")
        XCTAssertFalse(safe.description.contains("PRIVATE"))
        XCTAssertEqual(DiagnosticsLog.sanitize(["exception_code": "18446744073709551615"])["exception_code"], "18446744073709551615")
    }
}
