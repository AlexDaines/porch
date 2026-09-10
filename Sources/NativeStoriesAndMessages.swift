import SwiftUI

struct NativeStories: View {
    let people: [InstagramStoryPerson]
    @ObservedObject var client: InstagramDataClient
    @State private var selected: InstagramStoryPerson?
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                ForEach(people) { person in
                    Button { selected = person } label: {
                        HStack(spacing:12) {
                            Avatar(initials:String(person.username.prefix(2)).uppercased(),story:true)
                            Text(person.username).font(PorchTheme.title)
                            Spacer()
                            Image(systemName:"arrow.up.right").font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                        }.frame(minHeight:44).padding(.vertical,6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(person.username)'s story")
                    PorchRule()
                }
                if people.isEmpty { Text("No stories.").font(PorchTheme.body).foregroundStyle(PorchTheme.muted).padding(.top,40) }
            }.padding(.horizontal,20)
        }.accessibilityIdentifier("native-stories").refreshable { await client.load(.stories,refresh:true) }
            .sheet(item:$selected) { person in NativeStoryViewer(person:person,client:client) }
    }
}

struct NativeStoryViewer: View {
    let person: InstagramStoryPerson
    @ObservedObject var client: InstagramDataClient
    @Environment(\.dismiss) private var dismiss
    @State private var items: [InstagramPost] = []
    @State private var current = 0
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing:12) {
                    HStack {
                        Text(person.username).font(PorchTheme.title)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("Close story")
                    }
                    Spacer(minLength:0)
                    if loading { ProgressView() }
                    else if let error { LoadFailure(code:error,retry:{ if error == "signIn" { dismiss() } else { retry += 1 } },actionTitle:error == "signIn" ? "CLOSE STORY" : nil) }
                    else if let item = items.indices.contains(current) ? items[current] : nil, let media = item.media.first {
                        NativeMedia(media:media,maxHeight:max(180,min(600,geometry.size.height-180))).id(item.id)
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
                    } else { Text("This story has ended.").foregroundStyle(PorchTheme.muted) }
                    Spacer(minLength:0)
                }.padding(20).frame(minHeight:geometry.size.height)
            }
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone)
            .porchSheet()
            .task(id:retry) {
                loading = true; error = nil
                do { let result = try await client.request("story",identifier:person.id); items = result.posts; error = result.error }
                catch { self.error = InstagramDataClient.code(error) }
                loading = false
            }
    }
}

struct NativeInbox: View {
    let threads: [InstagramThread]
    @ObservedObject var client: InstagramDataClient
    @State private var selected: InstagramThread?
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                ForEach(threads) { thread in
                    Button { selected = thread } label: {
                        VStack(alignment:.leading,spacing:6) {
                            Text(thread.title).font(PorchTheme.title)
                            if !thread.preview.isEmpty { Text(thread.preview).font(PorchTheme.body).foregroundStyle(PorchTheme.muted).lineLimit(1) }
                        }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).padding(.vertical,8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    PorchRule()
                }
                if let code = client.inboxMoreError, code != "signIn" { LoadFailure(code:code) { Task { await client.moreConversations() } } }
                if client.inboxHasMore {
                    Button("MORE CONVERSATIONS") { Task { await client.moreConversations() } }
                        .font(PorchTheme.utility).frame(minHeight:44).padding(.vertical,16).disabled(client.inboxLoadingMore)
                }
                if client.inboxLoadingMore { ProgressView().padding(16) }
                if threads.count >= 200 { Eyebrow(text:"200 conversations loaded. Reload to start again.").padding(.vertical,16) }
                if threads.isEmpty { Text("No messages.").font(PorchTheme.body).foregroundStyle(PorchTheme.muted).padding(.top,40) }
            }.padding(.horizontal,20)
        }.accessibilityIdentifier("native-inbox").refreshable { await client.load(.messages,refresh:true) }
            .sheet(item:$selected) { thread in NativeConversation(thread:thread,client:client) }
    }
}

struct NativeConversation: View {
    @Environment(\.porchAccent) private var accent
    let thread: InstagramThread
    @ObservedObject var client: InstagramDataClient
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [InstagramMessage] = []
    @State private var loading = false
    @State private var error: String?
    @State private var draft = ""
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @State private var sendError: String?
    @State private var sent = false
    @State private var confirmUnlock = false
    private var sending: Bool { client.sendingThreads.contains(thread.id) }
    private var unconfirmed: Bool { client.pendingSends[thread.id] != nil && !sending }
    private var validDraft: Bool { !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && draft.utf16.count <= 1000 }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(thread.title).font(PorchTheme.title)
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("Close conversation")
            }.padding(.horizontal,20)
            PorchRule()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:12) {
                        if let error { LoadFailure(code:error,retry:{ if error == "signIn" { dismiss() } else { Task { await load() } } },actionTitle:error == "signIn" ? "CLOSE CONVERSATION" : nil) }
                        if hasOlder && messages.count < 200 {
                            Button("EARLIER MESSAGES") { Task { await load(older:true) } }
                                .font(PorchTheme.utility).frame(minHeight:44).disabled(loadingOlder)
                        }
                        if messages.count >= 200 { Eyebrow(text:"200 messages loaded. Reload to start again.") }
                        ForEach(messages) { message in
                            VStack(alignment:message.mine ? .trailing : .leading,spacing:4) {
                            if !message.mine, let sender = message.sender { Text(sender).font(PorchTheme.utility).foregroundStyle(PorchTheme.muted) }
                            Text(message.text).font(PorchTheme.body).textSelection(.enabled).padding(10)
                                .background(message.mine ? PorchTheme.surface : .clear)
                                .frame(maxWidth:.infinity,alignment:message.mine ? .trailing : .leading)
                                .accessibilityLabel(message.mine ? "You: \(message.text)" : message.text)
                            }.id(message.id)
                        }
                        if loading { ProgressView().frame(maxWidth:.infinity).padding(20) }
                    }.padding(20)
                }.refreshable { await load() }.scrollDismissesKeyboard(.interactively)
                    .onChange(of:messages.last?.id) { _, id in if let id { proxy.scrollTo(id,anchor:.bottom) } }
            }
            VStack(alignment:.leading,spacing:8) {
                if unconfirmed {
                    if confirmUnlock {
                        PorchConfirmation(title: "Allow another message?",
                            message: "The previous message may have arrived. This clears the warning and draft; it does not resend anything.",
                            actionTitle: "Allow another message", confirm: {
                                client.resolveSend(thread.id); draft = ""; sendError = nil; confirmUnlock = false
                            }, cancel: { confirmUnlock = false })
                    } else {
                        Text(LoadFailure.message("sendUnconfirmed")).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                        HStack {
                            Button("Check conversation") { Task { await load() } }.disabled(loading)
                            Spacer()
                            Button("I checked") { confirmUnlock = true }
                        }.font(PorchTheme.detail).frame(minHeight:44)
                    }
                } else if let sendError {
                    Text(LoadFailure.message(sendError)).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                } else if sent { Text("Sent").font(PorchTheme.utility).foregroundStyle(PorchTheme.muted).accessibilityIdentifier("message-sent") }
                HStack(alignment:.bottom,spacing:12) {
                    TextField("Message",text:$draft,prompt:Text("Message").foregroundStyle(PorchTheme.muted),axis:.vertical).font(PorchTheme.body).lineLimit(1...4)
                        .textFieldStyle(.plain).padding(.horizontal,10).padding(.vertical,8).frame(minHeight:44)
                        .background(PorchTheme.surface).accessibilityIdentifier("message-draft")
                    Button {
                        let text = draft
                        sent = false; sendError = nil
                        Task {
                            let failure = await client.sendText(text,to:thread.id)
                            if let failure { sendError = failure }
                            else {
                                messages.append(InstagramMessage(id:"local-"+UUID().uuidString,text:text,mine:true))
                                draft = ""; sent = true
                            }
                        }
                    } label: {
                        if sending { ProgressView().frame(width:44,height:44) }
                        else { Image(systemName:"arrow.up").font(PorchTheme.body).frame(width:44,height:44) }
                    }.disabled(!validDraft || sending || unconfirmed || loading || error != nil)
                        .foregroundStyle(validDraft && !sending && !unconfirmed && !loading && error == nil ? accent : PorchTheme.muted)
                        .accessibilityLabel("Send message").accessibilityIdentifier("send-message")
                }
                if draft.utf16.count > 1000 { Text("Up to 1,000 characters.").font(PorchTheme.detail).foregroundStyle(PorchTheme.muted) }
            }.padding(16)
        }.background(PorchTheme.canvas).foregroundStyle(PorchTheme.bone).preferredColorScheme(.dark)
            .porchSheet().interactiveDismissDisabled(sending)
            .onChange(of:draft) { _, value in client.keepDraft(value,for:thread.id) }
            .task { draft = client.drafts[thread.id] ?? ""; await load() }
    }
    private func load(older:Bool = false) async {
        guard !loading, !loadingOlder else { return }
        if older { loadingOlder = true } else { loading = true }
        error = nil
        let wasUnconfirmed = unconfirmed
        defer { loading = false; loadingOlder = false }
        do {
            let result = try await client.request(older ? "olderMessages" : "thread",identifier:thread.id)
            if let failure = result.error { error = failure }
            else {
                if older {
                    var existing = Set(messages.map(\.id))
                    let additions = result.messages.filter { existing.insert($0.id).inserted }
                    messages.insert(contentsOf:additions.suffix(max(0,200-messages.count)),at:0)
                } else { messages = result.messages }
                hasOlder = result.hasMore
                if wasUnconfirmed && client.pendingSends[thread.id] == nil { draft = ""; sendError = nil; sent = true }
            }
        } catch { self.error = InstagramDataClient.code(error) }
    }
}
