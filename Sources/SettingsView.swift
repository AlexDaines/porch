import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PorchModel
    @ObservedObject var browser: InstagramBrowser
    @ObservedObject var client: InstagramDataClient
    @State private var confirmClear = false
    @State private var clearing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if model.mode == .instagram {
                        Button("Reload") { Task { await client.load(model.tab, refresh: true) }; dismiss() }.frame(minHeight:44)
                    }
                    DisclosureGroup("About") {
                        VStack(alignment:.leading,spacing:16) {
                            Text("Free. Open source. No subscription, analytics or Porch account.")
                            Text("Native views read Instagram data through your local sign-in session. Feed, Stories and Messages stay separate. Reels and recognized ads are excluded before rendering.")
                            Text("Experimental, read-only client. Instagram can change its unofficial data routes. Sign-in stays on your device; content is held in memory. Instagram and its media servers still receive requests.")
                            Text("Following means accounts you follow, not necessarily people you know. Messages come from the accepted inbox; message requests are not loaded.")
                        }.font(.footnote).foregroundStyle(PorchTheme.muted).padding(.top,12)
                    }.tint(PorchTheme.muted)
                    Link("Source code",destination:URL(string:"https://github.com/AlexDaines/porch")!).frame(minHeight:44)
                    PorchRule()
                    Button("End session") { client.close(); browser.suspend(); model.mode = .welcome; dismiss() }
                        .frame(minHeight:44).accessibilityLabel("Finish session")
                    Button(clearing ? "Clearing…" : "Clear sign-in") { confirmClear = true }
                        .foregroundStyle(PorchTheme.muted).frame(minHeight:44).disabled(clearing).accessibilityIdentifier("clear-data")
                }.padding(20)
            }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone)
                .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.disabled(clearing) } }
                .toolbarBackground(PorchTheme.canvas,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
                .interactiveDismissDisabled(clearing)
                .confirmationDialog("Clear your Instagram sign-in?",isPresented:$confirmClear,titleVisibility:.visible) {
                    Button("Clear website data",role:.destructive) {
                        clearing = true; client.close(); model.mode = .welcome
                        Task { await browser.clearWebsiteData(); clearing = false; dismiss() }
                    }
                } message: { Text("Signs you out of Porch and clears its website data.") }
        }.presentationBackground(PorchTheme.canvas).preferredColorScheme(.dark).tint(PorchTheme.accent)
    }
}
