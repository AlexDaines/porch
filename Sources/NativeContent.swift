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
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(posts) { post in NativePostCard(post: post) }
                if posts.isEmpty {
                    Text("No posts.").font(.subheadline).foregroundStyle(PorchTheme.muted).padding(.top, 40)
                }
                if hasMore, let more {
                    Button("MORE POSTS", action: more).font(PorchTheme.utility).tracking(0.8).frame(minHeight:44).padding(.vertical,16)
                } else if !posts.isEmpty {
                    Eyebrow(text:"Caught up").padding(.vertical, 24)
                }
            }
        }.scrollIndicators(.hidden).background(PorchTheme.canvas)
            .accessibilityIdentifier("native-feed")
    }
}

struct NativePostCard: View {
    let post: InstagramPost
    @State private var expanded = false
    @State private var selectedImage = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(post.username).font(.headline)
                Spacer()
                if post.timestamp > 0 {
                    Text(Date(timeIntervalSince1970: post.timestamp), format: .dateTime.month(.abbreviated).day())
                        .font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                }
            }.padding(.horizontal, 20).padding(.top, 20)
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
                Text(post.caption).font(.subheadline).lineSpacing(3)
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
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player).frame(height: 380)
                    .accessibilityLabel("Video player")
            } else {
                NativePostImage(media: media)
                if let url = media.videoURL {
                    Button {
                        let next = AVPlayer(url: url)
                        player = next
                        next.play()
                    } label: {
                        Image(systemName: "play.fill").font(.title2).padding(20)
                            .background(PorchTheme.canvas.opacity(0.85), in: Circle())
                    }.accessibilityLabel("Play video")
                } else if media.isVideo == true {
                    Text("Video unavailable").font(.caption).padding(10).background(PorchTheme.canvas)
                }
            }
        }
        .onDisappear { stop() }
        .onChange(of: active) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
    }
    private func stop() { player?.pause(); player = nil }
}

struct NativePostImage: View {
    let media: InstagramPost.Media
    var body: some View {
        AsyncImage(url: media.imageURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Image(systemName: "photo").foregroundStyle(PorchTheme.muted).frame(maxWidth: .infinity, minHeight: 180)
            default: ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            }
        }.frame(maxWidth: .infinity, maxHeight: 420)
            .accessibilityLabel("Post photo").accessibilityIdentifier("native-post-image")
    }
}
