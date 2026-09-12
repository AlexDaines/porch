import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.porchAccent) private var accent
    @ObservedObject var model: PorchModel
    @ObservedObject var browser: InstagramBrowser
    @ObservedObject var client: InstagramDataClient
    @Binding var colorSelection: PorchColor
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var showColors = false
    @State private var showAbout = false
    @State private var showDiagnostics = false
    var body: some View {
        VStack(spacing: 0) {
            PorchSheetHeader(title: "Settings", closeLabel: "Done", closeDisabled: clearing, identifier: "settings-title") { dismiss() }
            PorchRule()
            ScrollView {
                VStack(spacing:12) {
                    if model.mode == .instagram {
                        Button("Reload") { Task { await client.load(model.tab, refresh: true) }; dismiss() }.frame(minHeight:44)
                    }
                    Button { showColors.toggle() } label: {
                        HStack(spacing: 8) {
                            Text("Color")
                            Text(colorSelection.name).foregroundStyle(PorchTheme.muted)
                            Image(systemName: showColors ? "chevron.up" : "chevron.down").font(PorchTheme.detail)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("settings-color").accessibilityValue(showColors ? "Expanded" : "Collapsed")
                    if showColors { ColorChoices(selection: $colorSelection, showsName: false) }
                    Button("About") { showAbout.toggle() }.frame(minHeight: 44)
                        .accessibilityValue(showAbout ? "Expanded" : "Collapsed")
                    if showAbout {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Free. Open source. No subscription, analytics or Porch account.")
                            Text("Native views read Instagram data through your local sign-in session. Feed, Stories and Messages stay separate. Reels and recognized ads are excluded before rendering.")
                            Text("Experimental client. Instagram can change its unofficial data routes. Sign-in stays on your device; content is held in memory. Instagram and its media servers still receive requests.")
                            Text("Following means accounts you follow, not necessarily people you know. Messages come from the accepted inbox; message requests are not loaded.")
                        }.font(PorchTheme.detail).foregroundStyle(PorchTheme.muted).padding(.top,12)
                    }
                    Link("Source code",destination:URL(string:"https://github.com/AlexDaines/porch")!).frame(minHeight:44).porchExternalControl()
                    Button { showDiagnostics = true } label: { Text("Diagnostics").frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }.accessibilityIdentifier("settings-diagnostics")
                    PorchRule()
                    Button("End session") { client.close(); browser.suspend(); model.mode = .welcome; dismiss() }
                        .frame(minHeight:44).accessibilityLabel("Finish session")
                    if confirmClear {
                        PorchConfirmation(title: "Clear your Instagram sign-in?",
                            message: "Signs you out of Porch and clears its website data.",
                            actionTitle: "Clear website data", destructive: true, confirm: {
                                confirmClear = false; clearing = true; client.close(); client.clearJournal(); model.mode = .welcome
                                Task { await browser.clearWebsiteData(); clearing = false; dismiss() }
                            }, cancel: { confirmClear = false })
                    } else {
                        Button(clearing ? "Clearing…" : "Clear sign-in") { confirmClear = true }
                            .foregroundStyle(PorchTheme.muted).frame(minHeight:44).disabled(clearing).accessibilityIdentifier("clear-data")
                    }
                }.frame(maxWidth: .infinity).padding(20).multilineTextAlignment(.center)
            }
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone)
            .porchSheet().porchTrace("Settings").interactiveDismissDisabled(clearing).tint(accent)
            .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
    }
}
