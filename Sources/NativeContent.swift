import SwiftUI
import AVKit

struct InstagramPost: Decodable, Identifiable {
    struct Media: Decodable, Identifiable {
        var id: String { url }
        let url: String
        let width: Double
        let height: Double
        let video: String?
        let isVideo: Bool?
        var alt: String? = nil
        var imageURL: URL? { Self.mediaURL(url) }
        var videoURL: URL? { video.flatMap(Self.mediaURL) }
        static func mediaURL(_ string: String) -> URL? {
            guard let value = URL(string: string), value.scheme == "https", let host = value.host,
                  value.user == nil, value.password == nil, value.port == nil || value.port == 443,
                  host.hasSuffix(".cdninstagram.com") || host.hasSuffix(".fbcdn.net") else { return nil }
            return value
        }
    }
    let id: String
    let username: String
    let caption: String
    let timestamp: Double
    let media: [Media]
}

struct NativeFeed: View {
    let posts: [InstagramPost]
    var hasMore = false
    var more: (() -> Void)?
    var moreLoading = false
    var moreError: String?
    var reachedSessionLimit = false
    var refresh: (() async -> Void)?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(posts) { post in NativePostCard(post: post) }
                if posts.isEmpty {
                    Text("No posts.").font(PorchTheme.body).foregroundStyle(PorchTheme.muted).padding(.top, 40)
                }
                if let moreError, let more, moreError != "signIn" {
                    LoadFailure(code:moreError,retry:{
                        if ["unavailable","unsupported"].contains(moreError) { Task { await refresh?() } } else { more() }
                    },actionTitle:["unavailable","unsupported"].contains(moreError) ? "RELOAD FEED" : nil)
                }
                if moreLoading { ProgressView().accessibilityLabel("Loading more posts") }
                if hasMore, let more {
                    Button("MORE POSTS", action: more).font(PorchTheme.utility).tracking(0.4).frame(minHeight:44).padding(.vertical,16).disabled(moreLoading)
                } else if !posts.isEmpty {
                    Eyebrow(text:reachedSessionLimit ? "Session limit reached. Reload to start again." : "No more posts").padding(.vertical, 24)
                }
            }
        }.scrollIndicators(.hidden).background(PorchTheme.canvas)
            .accessibilityIdentifier("native-feed").refreshable { await refresh?() }
    }
}

struct NativePostCard: View {
    let post: InstagramPost
    @State private var expanded = false
    @State private var selectedImage = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(post.username).font(PorchTheme.title)
                Spacer()
                if post.timestamp > 0 {
                    Text(Date(timeIntervalSince1970: post.timestamp), format: .dateTime.month(.abbreviated).day())
                        .font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                }
            }.padding(.horizontal, 20).padding(.top, 12)
            if post.media.count == 1, let media = post.media.first {
                NativeMedia(media: media)
            } else if !post.media.isEmpty {
                TabView(selection: $selectedImage) {
                    ForEach(Array(post.media.enumerated()), id: \.element.id) { index, media in
                        NativeMedia(media: media, active: selectedImage == index).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 380)
                Text("\(selectedImage + 1) / \(post.media.count)").font(PorchTheme.utility)
                    .foregroundStyle(PorchTheme.muted).padding(.horizontal, 20)
            }
            if !post.caption.isEmpty {
                Text(post.caption).font(PorchTheme.body).lineSpacing(3)
                    .lineLimit(expanded ? nil : 4).padding(.horizontal, 20)
                if !expanded && post.caption.count > 220 {
                    Button("MORE") { expanded = true }.font(PorchTheme.utility)
                        .frame(minHeight: 44).padding(.horizontal, 20).accessibilityLabel("More caption")
                }
            }
            PorchRule().padding(.horizontal, 20).padding(.top, 4)
        }.foregroundStyle(PorchTheme.bone).accessibilityElement(children:.contain).accessibilityIdentifier("native-post")
    }
}

struct NativeMedia: View {
    let media: InstagramPost.Media
    var active = true
    var maxHeight: CGFloat = 420
    @StateObject private var playback = MediaPlayback()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            if let player = playback.player {
                VideoPlayer(player: player).frame(height: maxHeight)
                    .accessibilityLabel("Video player").accessibilityIdentifier("video-player")
                if playback.state == .loading { ProgressView().padding(20).background(PorchTheme.canvas).accessibilityLabel("Loading video") }
            } else {
                NativePostImage(media: media, maxHeight: maxHeight)
                if let url = media.videoURL {
                    VStack(spacing: 12) {
                        if playback.state == .failed { Text("Couldn't play this video.").font(PorchTheme.body).padding(8).background(PorchTheme.canvas) }
                        Button { playback.start(url) } label: {
                            Image(systemName: playback.state == .failed ? "arrow.clockwise" : "play.fill").font(PorchTheme.body).frame(width:44,height:44)
                                .background(PorchTheme.canvas.opacity(0.85), in: Rectangle())
                        }.accessibilityLabel(playback.state == .failed ? "Retry video" : "Play video")
                            .accessibilityHint(media.alt?.isEmpty == false ? media.alt! : "Video preview")
                    }
                } else if media.isVideo == true {
                    Text("Video unavailable").font(PorchTheme.detail).padding(10).background(PorchTheme.canvas)
                }
            }
        }
        .onDisappear { playback.stop() }
        .onChange(of: active) { _, value in if !value { playback.stop() } }
        .onChange(of: scenePhase) { _, value in if value != .active { playback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop() }
    }
}

struct NativePostImage: View {
    let media: InstagramPost.Media
    var maxHeight: CGFloat = 420
    @State private var retry = UUID()
    var body: some View {
        #if BLIND_UI_FIXTURE
        BlindUIPhoto().frame(maxWidth: .infinity, maxHeight: maxHeight)
            .accessibilityLabel(media.alt ?? "Post photo").accessibilityIdentifier("native-post-image").accessibilityAddTraits(.isImage)
        #else
        AsyncImage(url: media.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit().accessibilityLabel(media.alt?.isEmpty == false ? media.alt! : "Post photo")
                    .accessibilityIdentifier("native-post-image").accessibilityAddTraits(.isImage)
            case .failure(let error):
                Button { retry = UUID() } label: { Label("Reload photo",systemImage:"arrow.clockwise").font(PorchTheme.utility).frame(maxWidth:.infinity,minHeight:180) }
                    .onAppear {
                        var fields = DiagnosticsLog.errorFields(error)
                        if let url = media.imageURL { fields["media_ref"] = DiagnosticsLog.shared.reference(url.absoluteString) }
                        DiagnosticsLog.shared.record(.imageFailed, fields)
                    }
            default: ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }.id(retry).frame(maxWidth: .infinity, maxHeight: maxHeight)
        #endif

    }
}
