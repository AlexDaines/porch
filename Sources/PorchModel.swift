import SwiftUI

@MainActor
final class PorchModel: ObservableObject {
    enum Mode { case welcome, sample, instagram, finished }
    enum Tab: String, CaseIterable { case feed = "Feed", stories = "Stories", messages = "Messages" }
    @Published var mode: Mode = .welcome
    @Published var tab: Tab = .feed
    @Published var showSettings = false

    init() {
        if ProcessInfo.processInfo.arguments.contains("--sample") { mode = .sample }
    }
}
