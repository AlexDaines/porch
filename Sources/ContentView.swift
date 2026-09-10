import SwiftUI

struct ContentView: View {
    @StateObject private var model = PorchModel()
    @StateObject private var browser = InstagramBrowser()
    @StateObject private var client = InstagramDataClient()
    @State private var showSignIn = false
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    tabControls
                    Spacer(minLength: 0)
                    sessionTools
                }
                VStack(alignment: .leading, spacing: 4) {
                    tabControls
                    HStack { Spacer(minLength: 0); sessionTools }
                }
            }.padding(.leading,20).padding(.trailing,8).padding(.bottom,8)
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
    @ViewBuilder private var tabControls: some View {
        ForEach([PorchModel.Tab.feed,.stories,.messages],id:\.self) { tab in
            Button { model.tab = tab } label: {
                Text(tab.rawValue.uppercased()).font(PorchTheme.utility).tracking(0.8)
                    .foregroundStyle(model.tab == tab ? PorchTheme.accent : PorchTheme.muted)
                    .fixedSize(horizontal:true,vertical:false)
                    .frame(minWidth:44,minHeight:44,alignment:.leading)
                    .padding(.bottom,4)
                    .overlay(alignment:.bottomLeading) {
                        if model.tab == tab { Rectangle().fill(PorchTheme.accent).frame(width:32,height:2) }
                    }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(tab.rawValue)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
        }
    }
    private var sessionTools: some View {
        HStack(spacing:0) {
            if model.mode == .sample { Eyebrow(text:"Sample").fixedSize() }
            Button { model.showSettings = true } label: {
                Image(systemName:"ellipsis").font(.system(size:18)).foregroundStyle(PorchTheme.muted).frame(width:44,height:44)
            }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
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
