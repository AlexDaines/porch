import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: DiagnosticsLog.Snapshot?
    @State private var busy = false
    @State private var confirmClear = false
    @State private var failure: String?
    @State private var exported: ExportedLog?
    private let log = DiagnosticsLog.shared

    var body: some View {
        VStack(spacing: 0) {
            PorchSheetHeader(title: "Diagnostics", closeLabel: "Done", identifier: "diagnostics-title") { dismiss() }
            PorchRule()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Porch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                        .font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                    Text("Detailed logs stay on this device for up to 14 days. Share them when something goes wrong.")
                    Text("No passwords, cookies, message text or media. Nothing is uploaded automatically.")
                        .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                    if let snapshot {
                        Text("\(snapshot.entries.count) events · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytes), countStyle: .file))")
                            .font(PorchTheme.utility).accessibilityIdentifier("diagnostics-count")
                        if let event = lastFailure(snapshot) {
                            VStack(spacing: 6) {
                                Text("Last failure").font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                                Text(failureSummary(event)).font(PorchTheme.utility).accessibilityIdentifier("diagnostics-last-failure")
                                Text(event.timestamp, format: .dateTime.month().day().hour().minute().second())
                                    .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                            }
                        }
                        if snapshot.writeFailures > 0 || snapshot.unreadableLines > 0 || !snapshot.directoryAvailable {
                            Text("Some log entries could not be saved or read. The export includes storage error counts.")
                                .font(PorchTheme.detail).accessibilityIdentifier("diagnostics-storage-warning")
                        }
                    }
                    if let failure { Text(failure).font(PorchTheme.detail) }
                    Button {
                        busy = true; failure = nil
                        Task {
                            do { exported = ExportedLog(url: try await log.export()) }
                            catch { failure = "Couldn't prepare the log. Check your device's available storage and try again." }
                            snapshot = await log.snapshot(); busy = false
                        }
                    } label: { Text(busy ? "Preparing…" : "Share log").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .disabled(busy).porchExternalControl().accessibilityIdentifier("diagnostics-share")
                    Button { Task { snapshot = await log.snapshot() } } label: {
                        Text("Refresh").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.disabled(busy)
                    if confirmClear {
                        PorchConfirmation(title: "Clear diagnostic logs?", message: "Your sign-in and conversations stay as they are.",
                            actionTitle: "Clear logs", destructive: true, confirm: {
                                confirmClear = false; busy = true; failure = nil
                                Task {
                                    do { try await log.clear() }
                                    catch { failure = "Some logs couldn't be cleared. Try again when storage is available." }
                                    snapshot = await log.snapshot(); busy = false
                                }
                            }, cancel: { confirmClear = false })
                    } else {
                        Button { confirmClear = true } label: { Text("Clear log").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.disabled(busy)
                            .foregroundStyle(PorchTheme.muted)
                    }
                }.font(PorchTheme.body).frame(maxWidth: .infinity).padding(24).multilineTextAlignment(.center)
            }
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).porchSheet().porchTrace("Diagnostics")
            .task { snapshot = await log.snapshot() }
            .sheet(item: $exported) { LogShareSheet(url: $0.url) }
    }
    private func lastFailure(_ snapshot: DiagnosticsLog.Snapshot) -> DiagnosticsLog.Entry? {
        snapshot.entries.last { event in
            if let result = event.fields["result"], result != "none", result != "cancelled" { return true }
            return [.requestFailed, .authPageFailed, .mediaFailed, .imageFailed, .iosCrash, .iosHang].contains(event.event)
        }
    }
    private func failureSummary(_ event: DiagnosticsLog.Entry) -> String {
        [event.fields["operation"] ?? event.event.rawValue, event.fields["http"].map { "HTTP \($0)" }, event.fields["result"]]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ExportedLog: Identifiable { let id = UUID(); let url: URL }
private struct LogShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
