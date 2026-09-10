import SwiftUI

struct ContentView: View {
    @StateObject private var model = PorchModel()
    @StateObject private var browser = InstagramBrowser()
    @StateObject private var client = InstagramDataClient()
    @State private var showSignIn = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var nativeTab: PorchModel.Tab? { model.mode == .instagram ? model.tab : nil }

    var body: some View {
        ZStack {
            PorchTheme.canvas.ignoresSafeArea()
            switch model.mode {
            case .welcome, .finished:
                WelcomeView(connect:connect,sample:{ model.mode = .sample; model.tab = .feed })
            case .sample, .instagram: session
            }
        }.foregroundStyle(PorchTheme.bone).preferredColorScheme(.dark).tint(PorchTheme.accent)
            .sheet(isPresented:$model.showSettings) { SettingsView(model:model,browser:browser,client:client) }
            .sheet(isPresented:$showSignIn,onDismiss:{
                browser.suspend(); client.close()
                if model.mode == .instagram { Task { await client.load(model.tab) } }
            }) { InstagramSignIn(browser:browser) }
            .onChange(of:browser.authenticated) { _, value in if value { showSignIn = false } }
            .onChange(of:model.mode) { _, mode in if mode != .instagram { client.close() } }
            .task(id:nativeTab) {
                if let tab = nativeTab {
                    await client.load(tab)
                    if client.error == "signIn" { signIn() }
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--native") { connect() }
                if ProcessInfo.processInfo.arguments.contains("--sign-in") { signIn() }
            }
    }
    private var session: some View {
        VStack(spacing:0) {
            HStack(spacing:dynamicTypeSize.isAccessibilitySize ? 8 : 18) {
                ForEach([PorchModel.Tab.feed,.stories,.messages],id:\.self) { tab in
                    Button { model.tab = tab } label: {
                        Text(tab.rawValue).font(.subheadline.weight(model.tab == tab ? .semibold : .regular))
                            .foregroundStyle(model.tab == tab ? PorchTheme.bone : PorchTheme.muted)
                            .frame(minWidth:44,minHeight:44,alignment:.leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(tab.rawValue)")
                        .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
                Spacer(minLength:0)
                if model.mode == .sample { Text("SAMPLE").font(.caption2).foregroundStyle(PorchTheme.muted) }
                Button { model.showSettings = true } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }
                    .accessibilityLabel("Settings").accessibilityIdentifier("settings")
            }.padding(.leading,16).padding(.trailing,4)
            PorchRule()
            if model.mode == .sample {
                switch model.tab {
                case .stories: SampleStories()
                case .messages: SampleInbox()
                default: SampleFeed(finish:finish)
                }
            } else { liveContent }
        }
    }
    @ViewBuilder private var liveContent: some View {
        if let error = client.error {
            VStack(spacing:20) {
                Text(error == "signIn" ? "Sign in to Instagram." : error == "rateLimited" ? "Try again in a little while." : "Couldn't load this view.")
                    .font(.subheadline).foregroundStyle(PorchTheme.muted)
                Button(error == "signIn" ? "Sign in" : "Try again") {
                    if error == "signIn" { signIn() } else { Task { await client.load(model.tab, refresh: true) } }
                }.font(.subheadline).frame(minHeight:44)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        } else {
            ZStack {
                switch model.tab {
                case .stories: NativeStories(people:client.stories,client:client)
                case .messages: NativeInbox(threads:client.threads,client:client)
                default: NativeFeed(posts:client.posts,hasMore:client.hasMore,more:{ Task { await client.morePosts() } })
                }
                if client.loading { ProgressView().padding(16).background(PorchTheme.canvas) }
            }
        }
    }
    private func connect() { model.tab = .feed; model.mode = .instagram }
    private func signIn() { browser.connect(); showSignIn = true }
    private func finish() { client.close(); browser.suspend(); model.mode = .welcome }
}
