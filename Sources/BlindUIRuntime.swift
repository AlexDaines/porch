#if BLIND_UI_FIXTURE && !DEBUG
#error("PorchBlindUI is a Debug-only offline application")
#endif

#if DEBUG
import Foundation

@MainActor
final class BlindUIRuntime {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PorchBlindUI", isDirectory: true)
    static let configuration: BlindUILaunchConfiguration? = {
        #if BLIND_UI_FIXTURE
        return BlindUILaunchConfiguration.parse(ProcessInfo.processInfo.arguments, root: root)
        #else
        return nil
        #endif
    }()
    static let shared: BlindUIRuntime? = configuration.map(BlindUIRuntime.init)
    let configuration: BlindUILaunchConfiguration
    let store: BlindUIStore
    let defaults: UserDefaults
    private var transport: BlindUITransport?
    private weak var client: InstagramDataClient?
    private var poll: Task<Void, Never>?
    private var lastAction: DiagnosticAction?
    private var closeStarted = false
    private var observedCommand: String?
    private init(configuration: BlindUILaunchConfiguration) {
        self.configuration = configuration
        store = BlindUIStore(runID: configuration.runID, directory: configuration.directory)
        defaults = UserDefaults(suiteName: configuration.defaultsName)!
        if !store.resumed {
            defaults.removePersistentDomain(forName: configuration.defaultsName)
            defaults.set(true, forKey: "porch.appearance.introComplete")
            defaults.set("sage", forKey: "porch.appearance.color")
        }
        let manifest = ["schema": "blind-ui/configuration-v1", "run_id": configuration.runID, "control": configuration.control.rawValue]
        let path = configuration.directory.appendingPathComponent("configuration.json")
        do {
            if store.resumed {
                let saved = try JSONDecoder().decode([String: String].self, from: BlindUIStore.read(path))
                if saved != manifest { store.invalidate() }
            } else { try BlindUIStore.atomic(manifest, at: path) }
        } catch { store.invalidate() }
    }
    static func start() {
        guard let runtime = shared else { return }
        DiagnosticsLog.shared.setActionContext(.init(runID: runtime.configuration.runID))
        runtime.poll = Task { @MainActor [weak runtime] in
            while !Task.isCancelled {
                guard let runtime else { return }
                // File IO stays off the UI executor. The acknowledgement is written
                // only after the cached context is installed, before the broker taps.
                let directory = runtime.configuration.directory
                let packet = await Task.detached(priority: .utility) { readPacket(directory) }.value
                await runtime.apply(packet)
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    func makeClient() -> InstagramDataClient {
        let transport = BlindUITransport(store: store, control: configuration.control)
        self.transport = transport
        let client = InstagramDataClient(transport: transport, defaults: defaults)
        self.client = client
        return client
    }
    struct Packet: Sendable {
        var action: DiagnosticAction?
        var commandID: String?
        var malformed = false
    }
    nonisolated static func readPacket(_ directory: URL) -> Packet {
        var packet = Packet()
        func read(_ name: String) throws -> [String: Any]? {
            let path = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            guard let data = try JSONSerialization.jsonObject(with: BlindUIStore.read(path)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            return data
        }
        do {
            if let object = try read("action-context.json") {
                guard object["schema"] as? String == "blind-ui/action-context-v1",
                      Set(object.keys) == ["schema", "run_id", "action_id", "broker_sequence"],
                      let runID = object["run_id"] as? String, UUID(uuidString: runID) != nil,
                      let actionID = object["action_id"] as? String, UUID(uuidString: actionID) != nil,
                      let number = object["broker_sequence"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue),
                      number.intValue > 0, number.intValue <= 100_000 else { throw CocoaError(.fileReadCorruptFile) }
                packet.action = .init(runID: runID.lowercased(), actionID: actionID, brokerSequence: number.intValue)
            }
        } catch { packet.malformed = true }
        // A malformed action invalidates scoring, but must not prevent the
        // recorder from closing that invalid run and preserving its receipt.
        do {
            if let object = try read("control.json") {
                guard object["schema"] as? String == "blind-ui/control-v1", object["command"] as? String == "close",
                      Set(object.keys) == ["schema", "run_id", "command", "command_id"],
                      object["run_id"] as? String == directory.lastPathComponent,
                      let command = object["command_id"] as? String, UUID(uuidString: command) != nil else { throw CocoaError(.fileReadCorruptFile) }
                packet.commandID = command
            }
        } catch { packet.malformed = true }
        return packet
    }
    private func apply(_ packet: Packet) async {
        if packet.malformed { store.invalidate() }
        if let action = packet.action, !closeStarted, action != lastAction {
            if action.runID == configuration.runID,
               (action.brokerSequence ?? 0) > (lastAction?.brokerSequence ?? 0),
               action.actionID != lastAction?.actionID {
                lastAction = action
                DiagnosticsLog.shared.setActionContext(action)
                DiagnosticsLog.shared.record(.actionApplied, action.fields.merging(["source": "fixture"]) { _, new in new })
                do {
                    try BlindUIStore.atomic(["schema": "blind-ui/action-context-ack-v1", "run_id": action.runID,
                        "action_id": action.actionID!, "broker_sequence": action.brokerSequence!] as [String: Any],
                        at: configuration.directory.appendingPathComponent("action-context-ack.json"))
                } catch { store.invalidate() }
            } else { store.invalidate() }
        }
        if let commandID = packet.commandID, !closeStarted {
            observedCommand = commandID
            transport?.closing = true // No new acceptance after recorder close begins.
        }
        guard let commandID = observedCommand, !closeStarted, client?.sendingThreads.isEmpty != false else { return }
        closeStarted = true
        DiagnosticsLog.shared.record(.fixtureClosed, ["source": "fixture"])
        await DiagnosticsLog.shared.flush()
        let health = await DiagnosticsLog.shared.snapshot()
        store.close(commandID: commandID, diagnosticsHealthy: health.directoryAvailable && health.writeFailures == 0 && health.unreadableLines == 0 && !health.entries.contains(where: { $0.event == .logsCleared }))
        poll?.cancel()
    }
}
#endif
