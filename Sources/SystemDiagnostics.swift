import Foundation
import UIKit
import Network
import MetricKit

// No crash handlers or signal interception. MetricKit reports arrive when iOS
// makes them available; recording never sends them to a service.
final class SystemDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = SystemDiagnostics()
    private let log = DiagnosticsLog.shared
    private let network = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []
    private var started = false

    @MainActor func start() {
        guard !started else { return }; started = true
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let fixture = args.contains("--uat-fixture") || args.contains("--sample") || args.contains("--appearance-fixture")
        let source = fixture ? "fixture" : "app"
        #else
        let source = "app"
        #endif
        log.record(.appLaunch, DiagnosticsLog.environment().merging(
            ["low_power": String(ProcessInfo.processInfo.isLowPowerModeEnabled), "source": source], uniquingKeysWith: { _, new in new }))
        let notifications: [(Notification.Name, DiagnosticsLog.Event, String)] = [
            (UIApplication.didBecomeActiveNotification, .lifecycle, "active"),
            (UIApplication.willResignActiveNotification, .lifecycle, "inactive"),
            (UIApplication.didEnterBackgroundNotification, .lifecycle, "background"),
            (UIApplication.willEnterForegroundNotification, .lifecycle, "foreground"),
            (UIApplication.willTerminateNotification, .lifecycle, "terminated"),
            (UIApplication.didReceiveMemoryWarningNotification, .memoryWarning, "")]
        for (name, event, state) in notifications {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [log] _ in
                log.record(event, state.isEmpty ? [:] : ["state": state])
            })
        }
        for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [log] _ in
                log.record(.thermal, Self.powerState())
            })
        }
        log.record(.thermal, Self.powerState())
        network.pathUpdateHandler = { [log] path in
            let state: String
            switch path.status {
            case .satisfied: state = "satisfied"
            case .unsatisfied: state = "unsatisfied"
            case .requiresConnection: state = "requiresConnection"
            @unknown default: state = "unknown"
            }
            let types: [(NWInterface.InterfaceType, String)] = [(.wifi,"wifi"),(.cellular,"cellular"),(.wiredEthernet,"wiredEthernet"),(.loopback,"loopback"),(.other,"other")]
            log.record(.network, ["state": state, "interface": types.first { path.usesInterfaceType($0.0) }?.1 ?? "none",
                "expensive": String(path.isExpensive), "constrained": String(path.isConstrained),
                "ipv4": String(path.supportsIPv4), "ipv6": String(path.supportsIPv6), "dns": String(path.supportsDNS)])
        }
        network.start(queue: DispatchQueue(label: "dev.alex.porch.network-diagnostics", qos: .utility))
        MXMetricManager.shared.add(self)
    }

    private static func powerState() -> [String: String] {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        return ["state": state, "low_power": String(ProcessInfo.processInfo.isLowPowerModeEnabled)]
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            func fields(_ diagnostic: MXDiagnostic, _ tree: MXCallStackTree) -> [String: String] {
                var result = Self.stackFields(tree.jsonRepresentation())
                result["source"] = "metrickit"
                result["app_version"] = diagnostic.applicationVersion
                result["build"] = diagnostic.metaData.applicationBuildVersion
                result["period_start"] = String(payload.timeStampBegin.timeIntervalSince1970)
                result["period_end"] = String(payload.timeStampEnd.timeIntervalSince1970)
                return result
            }
            for crash in payload.crashDiagnostics ?? [] {
                var values = fields(crash, crash.callStackTree)
                values["exception_type"] = crash.exceptionType?.stringValue
                values["exception_code"] = crash.exceptionCode?.stringValue
                values["signal"] = crash.signal?.stringValue
                log.record(.iosCrash, values)
            }
            for hang in payload.hangDiagnostics ?? [] {
                var values = fields(hang, hang.callStackTree)
                values["duration_seconds"] = String(hang.hangDuration.converted(to: .seconds).value)
                log.record(.iosHang, values)
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                var values = fields(cpu, cpu.callStackTree)
                values["duration_seconds"] = String(cpu.totalCPUTime.converted(to: .seconds).value)
                log.record(.iosCPUException, values)
            }
            for disk in payload.diskWriteExceptionDiagnostics ?? [] {
                var values = fields(disk, disk.callStackTree)
                values["memory_bytes"] = String(disk.totalWritesCaused.converted(to: .bytes).value)
                log.record(.iosDiskException, values)
            }
            for launch in payload.appLaunchDiagnostics ?? [] {
                var values = fields(launch, launch.callStackTree)
                values["duration_seconds"] = String(launch.launchDuration.converted(to: .seconds).value)
                log.record(.iosLaunchDiagnostic, values)
            }
        }
    }

    // Read only stack structure and binary coordinates. Exception text, paths,
    // binary names, thread names and register contents never reach the logger.
    static func stackFields(_ data: Data) -> [String: String] {
        guard data.count <= 8 * 1_024 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var frames: [String] = [], visited = 0, truncated = false
        func walk(_ value: Any, depth: Int) {
            guard depth < 128, visited < 4_096 else { truncated = true; return }
            visited += 1
            if let dictionary = value as? [String: Any] {
                if let uuid = dictionary["binaryUUID"] as? String, UUID(uuidString: uuid) != nil,
                   let offset = dictionary["offsetIntoBinaryTextSegment"] as? NSNumber,
                   offset.doubleValue >= 0 {
                    if frames.count < 64 { frames.append(uuid + "@" + offset.stringValue) }
                    else { truncated = true }
                }
                for key in ["callStacks", "callStackRootFrames", "subFrames"] {
                    if let child = dictionary[key] { walk(child, depth: depth + 1) }
                }
            } else if let array = value as? [Any] {
                for child in array.prefix(4_096) { walk(child, depth: depth + 1) }
                if array.count > 4_096 { truncated = true }
            }
        }
        walk(object, depth: 0)
        return DiagnosticsLog.sanitize(["frames": frames.joined(separator: ","), "frame_count": String(frames.count), "frames_truncated": String(truncated)])
    }
}
