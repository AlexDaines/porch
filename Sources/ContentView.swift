import SwiftUI

struct ContentView: View {
    @StateObject private var model = PorchModel()
    @StateObject private var browser = InstagramBrowser()
    @StateObject private var client = InstagramDataClient.appClient()
    @State private var showSignIn = false
    @AppStorage("porch.appearance.color", store: AppearancePreferences.store) private var colorName = PorchColor.sage.rawValue
    @AppStorage("porch.appearance.introComplete", store: AppearancePreferences.store) private var introComplete = false
    private var colorSelection: Binding<PorchColor> {
        Binding(get: { PorchColor(rawValue: colorName) ?? .sage }, set: { colorName = $0.rawValue })
    }
    private var accent: Color { colorSelection.wrappedValue.color }
    private var nativeTab: PorchModel.Tab? { model.mode == .instagram ? model.tab : nil }

    var body: some View {
        ZStack {
            PorchTheme.canvas.ignoresSafeArea()
            if !introComplete && !AppearancePreferences.bypassIntro {
                ColorWelcomeView(selection: colorSelection) { introComplete = true }
            } else {
                switch model.mode {
                case .welcome, .finished:
                    WelcomeView(connect:connect,sample:{ model.mode = .sample; model.tab = .feed })
                case .sample, .instagram: session
                }
            }
        }.font(PorchTheme.body).foregroundStyle(PorchTheme.bone).preferredColorScheme(.dark).tint(accent).buttonStyle(.plain)
            .sheet(isPresented:$model.showSettings) { SettingsView(model:model,browser:browser,client:client,colorSelection:colorSelection) }
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
            .environment(\.porchAccent, accent)
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
            }.padding(.leading,20).padding(.trailing,8).padding(.bottom,4)
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
                Text(tab.rawValue.uppercased()).font(PorchTheme.utility).tracking(0.4)
                    .foregroundStyle(model.tab == tab ? accent : PorchTheme.muted)
                    .fixedSize(horizontal:true,vertical:false)
                    .frame(minWidth:44,minHeight:44,alignment:.leading)
                    .padding(.bottom,4)
                    .overlay(alignment:.bottomLeading) {
                        if model.tab == tab { Rectangle().fill(accent).frame(width:24,height:1) }
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
                Image(systemName:"ellipsis").font(.system(size:14)).foregroundStyle(PorchTheme.muted).frame(width:44,height:44)
            }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
        }
    }
    @ViewBuilder private var liveContent: some View {
        VStack(spacing:0) {
            if let error = client.error {
                LoadFailure(code:error) {
                    if error == "signIn" { signIn() } else { Task { await client.load(model.tab,refresh:true) } }
                }
            }
            if client.error == nil || client.hasLoadedCurrentTab {
                ZStack {
                    switch model.tab {
                    case .stories: NativeStories(people:client.stories,client:client)
                    case .messages: NativeInbox(threads:client.threads,client:client)
                    case .feed:
                        NativeFeed(posts:client.posts,hasMore:client.hasMore,more:{ Task { await client.morePosts() } },
                            moreLoading:client.moreLoading,moreError:client.moreError,reachedSessionLimit:client.reachedSessionLimit,
                            refresh:{ await client.load(.feed,refresh:true) })
                    }
                    if client.loading && !client.hasLoadedCurrentTab { ProgressView().padding(16).background(PorchTheme.canvas) }
                }
            } else { Spacer() }
        }
    }
    private func connect() { model.tab = .feed; model.mode = .instagram }
    private func signIn() { browser.connect(); showSignIn = true }
    private func finish() { client.close(); browser.suspend(); model.mode = .welcome }
}
