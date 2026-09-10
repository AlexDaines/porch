import SwiftUI

struct NativeStories: View {
    let people: [InstagramStoryPerson]
    let client: InstagramDataClient
    @State private var selected: InstagramStoryPerson?
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                ForEach(people) { person in
                    Button { selected = person } label: {
                        HStack(spacing:16) {
                            Avatar(initials:String(person.username.prefix(2)).uppercased(),story:true)
                            Text(person.username).font(.headline)
                            Spacer()
                            Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(PorchTheme.muted)
                        }.padding(.vertical,16).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(person.username)'s story")
                    PorchRule()
                }
                if people.isEmpty { Text("No stories.").font(.subheadline).foregroundStyle(PorchTheme.muted).padding(.top,40) }
            }.padding(.horizontal,20)
        }.accessibilityIdentifier("native-stories")
            .sheet(item:$selected) { person in NativeStoryViewer(person:person,client:client) }
    }
}

struct NativeStoryViewer: View {
    let person: InstagramStoryPerson
    let client: InstagramDataClient
    @Environment(\.dismiss) private var dismiss
    @State private var items: [InstagramPost] = []
    @State private var current = 0
    @State private var loading = true
    @State private var failed = false
    var body: some View {
        VStack(spacing:20) {
            HStack {
                Text(person.username).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("Close story")
            }
            Spacer(minLength:0)
            if loading { ProgressView() }
            else if let item = items.indices.contains(current) ? items[current] : nil, let media = item.media.first {
                NativeMedia(media:media).id(item.id)
                HStack {
                    Button { current = max(0,current-1) } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }
                        .disabled(current == 0).accessibilityLabel("Previous story")
                    Spacer()
                    Text("\(current+1) / \(items.count)").font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                    Spacer()
                    Button { if current+1 < items.count { current += 1 } else { dismiss() } } label: {
                        Image(systemName:current+1 < items.count ? "chevron.right" : "checkmark").frame(width:44,height:44)
                    }.accessibilityLabel(current+1 < items.count ? "Next story" : "Close story")
                }
            } else { Text(failed ? "Couldn't load this story." : "This story has ended.").foregroundStyle(PorchTheme.muted) }
            Spacer(minLength:0)
        }.padding(20).background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone)
            .preferredColorScheme(.dark).presentationBackground(PorchTheme.canvas)
            .task {
                do { let result = try await client.request("story",identifier:person.id); items = result.posts; failed = result.error != nil }
                catch { failed = true }
                loading = false
            }
    }
}

struct NativeInbox: View {
    let threads: [InstagramThread]
    let client: InstagramDataClient
    @State private var selected: InstagramThread?
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                ForEach(threads) { thread in
                    Button { selected = thread } label: {
                        VStack(alignment:.leading,spacing:6) {
                            Text(thread.title).font(.headline)
                            if !thread.preview.isEmpty { Text(thread.preview).font(.subheadline).foregroundStyle(PorchTheme.muted).lineLimit(1) }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,18).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    PorchRule()
                }
                if threads.isEmpty { Text("No messages.").font(.subheadline).foregroundStyle(PorchTheme.muted).padding(.top,40) }
            }.padding(.horizontal,20)
        }.accessibilityIdentifier("native-inbox")
            .sheet(item:$selected) { thread in NativeConversation(thread:thread,client:client) }
    }
}

struct NativeConversation: View {
    let thread: InstagramThread
    let client: InstagramDataClient
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [InstagramMessage] = []
    @State private var loading = true
    @State private var failed = false
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(thread.title).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("Close conversation")
            }.padding(.horizontal,20)
            PorchRule()
            ScrollView {
                VStack(spacing:16) {
                    ForEach(messages) { message in
                        Text(message.text).font(.body).padding(12).background(message.mine ? PorchTheme.surface : .clear)
                            .frame(maxWidth:.infinity,alignment:message.mine ? .trailing : .leading)
                    }
                    if loading { ProgressView().padding(30) }
                    if failed { Text("Couldn't load these messages.").foregroundStyle(PorchTheme.muted).padding(30) }
                }.padding(16)
            }
            Text("Read-only").font(PorchTheme.utility).foregroundStyle(PorchTheme.muted).padding(12)
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).preferredColorScheme(.dark)
            .presentationBackground(PorchTheme.canvas)
            .task {
                do { let result = try await client.request("thread",identifier:thread.id); messages = result.messages; failed = result.error != nil }
                catch { failed = true }
                loading = false
            }
    }
}
