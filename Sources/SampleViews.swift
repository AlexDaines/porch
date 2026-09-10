import SwiftUI

enum SampleContent {
    static let names = ["Maya", "Jules", "Ari", "Sam"]
    static let initials = ["MK", "JL", "AS", "SR"]
    static var landscape: UIImage? {
        guard let path = Bundle.main.path(forResource: "lake", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
struct SampleLandscape: View {
    let height: CGFloat
    var body: some View {
        GeometryReader { geometry in
            if let photo = SampleContent.landscape {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .accessibilityLabel("Sample landscape: a cabin and mountains reflected in a still lake")
            }
        }.frame(height: height)
    }
}
struct SampleFeed: View {
    let finish: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("maya.kim").font(.headline)
                    Spacer()
                    Eyebrow(text: "2h")
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
                SampleLandscape(height: 320)
                Text("Took the long way home.").font(.subheadline).padding(.horizontal, 20).padding(.vertical, 16)
                PorchRule().padding(.horizontal, 20)
                HStack {
                    Eyebrow(text: "Caught up")
                    Spacer()
                    Button("END", action: finish).font(PorchTheme.utility).foregroundStyle(PorchTheme.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing).accessibilityLabel("Finish session")
                }.padding(.horizontal, 20).padding(.top, 8)
            }
        }.scrollIndicators(.hidden)
    }
}
struct SampleStories: View {
    @State private var story: Int?
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    Button { story = index } label: {
                        HStack(spacing: 14) {
                            Avatar(initials: SampleContent.initials[index], size: 44, story: true)
                            Text(SampleContent.names[index]).font(.headline)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(PorchTheme.muted)
                        }.padding(.vertical, 16).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(SampleContent.names[index])'s sample story")
                    PorchRule()
                }
            }.padding(.horizontal, 20)
        }.sheet(isPresented: Binding(get: { story != nil }, set: { if !$0 { story = nil } })) { SampleStory(start: story ?? 0) }
    }
}
struct SampleStory: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current: Int
    init(start: Int) { _current = State(initialValue: start) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(SampleContent.names[current]).font(.headline)
                    Spacer()
                    Eyebrow(text: "Sample · \(current + 1)/4")
                    Button("CLOSE") { dismiss() }.font(PorchTheme.utility).frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(PorchTheme.accent).accessibilityLabel("Close")
                }
                SampleLandscape(height: 400)
                Text(["Somewhere with no agenda.", "A good day to take the scenic route.", "Wish you were here.", "See you when we're back."][current]).font(.body)
                Button(current == 3 ? "DONE" : "NEXT") {
                    if current == 3 { dismiss() } else { current += 1 }
                }.buttonStyle(PorchButtonStyle(filled: false))
                    .accessibilityLabel(current == 3 ? "All done" : "Next story")
            }.padding(20)
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).preferredColorScheme(.dark)
    }
}
struct SampleInbox: View {
    @State private var selected: Int?
    private let messages = ["Coffee on Sunday?", "That looks like a good detour.", "Made it home. Thank you for today."]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3) { index in
                    Button { selected = index } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(SampleContent.names[index]).font(.headline)
                                Text(messages[index]).font(.subheadline).foregroundStyle(PorchTheme.muted).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 18).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    PorchRule()
                }
            }.padding(.horizontal, 20)
        }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(SampleContent.names[selected ?? 0]).font(.headline)
                    Spacer()
                    Button("CLOSE") { selected = nil }.font(PorchTheme.utility).foregroundStyle(PorchTheme.accent).frame(minHeight: 44)
                }
                PorchRule()
                Text(messages[selected ?? 0]).font(.body)
                Eyebrow(text: "Sample · sending unavailable")
            }.padding(20).presentationDetents([.medium]).presentationBackground(PorchTheme.canvas).foregroundStyle(PorchTheme.bone)
        }
    }
}
