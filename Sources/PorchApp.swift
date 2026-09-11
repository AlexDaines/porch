import SwiftUI

@main
struct PorchApp: App {
    init() { SystemDiagnostics.shared.start() }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
