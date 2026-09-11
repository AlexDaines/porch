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
        #if DEBUG
        // Enter native test journeys before SwiftUI can mount the welcome page
        // and start its unrelated WebKit saved-session probe.
        if ProcessInfo.processInfo.arguments.contains("--native") { mode = .instagram }
        #endif
    }
}
