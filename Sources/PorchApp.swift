import SwiftUI

@main
struct PorchApp: App {
    init() {
        #if BLIND_UI_FIXTURE
        _ = BlindUIRuntime.shared
        BlindUIRuntime.start()
        #endif
        SystemDiagnostics.shared.start()
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
