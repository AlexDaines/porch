import SwiftUI

// Closed logical view states complement screenshots; they do not prove which
// pixels a participant saw or establish delivery. Never record view text.
private struct PorchViewDiagnostics: ViewModifier {
    let view: String
    let state: String
    var identifier: String?
    private func record(_ value: String) {
        var fields = ["view": view, "state": value]
        if let identifier { fields["thread_ref"] = DiagnosticsLog.shared.reference("identifier:" + identifier) }
        DiagnosticsLog.shared.record(.viewState, fields)
    }
    func body(content: Content) -> some View {
        content.onAppear { record(state) }
            .onChange(of: state) { _, value in record(value) }
            .onDisappear { record("hidden") }
    }
}
extension View {
    @ViewBuilder func porchExternalControl() -> some View {
        #if BLIND_UI_FIXTURE
        self.disabled(true)
        #else
        self
        #endif
    }
    func porchTrace(_ view: String, state: String = "visible", identifier: String? = nil) -> some View {
        modifier(PorchViewDiagnostics(view: view, state: state, identifier: identifier))
    }
}
