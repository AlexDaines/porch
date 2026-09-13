import Foundation

extension InstagramDataClient {
    @MainActor static func appClient() -> InstagramDataClient {
        #if BLIND_UI_FIXTURE
        guard let runtime = BlindUIRuntime.shared else { fatalError("Invalid offline fixture configuration") }
        return runtime.makeClient()
        #else
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uat-fixture") {
            let store = UserDefaults(suiteName:"porch.ui-fixture")!
            store.removePersistentDomain(forName:"porch.ui-fixture")
            return InstagramDataClient(transport:UITestTransport(),defaults:store)
        }
        #endif
        return InstagramDataClient()
        #endif
    }
}

#if DEBUG
// This transport never accesses Instagram and is absent from Release builds.
@MainActor
private final class UITestTransport: InstagramTransport {
    private var feedLoads = 0
    private var feedPages = 0
    private var delayedReconciliation = false
    private var messages = [InstagramMessage(id:"1",text:"A fictional conversation for UAT checks.",mine:false)]
    func execute(_ operation:String,identifier:String,text:String,context:String,feedCount:Int = 10) async throws -> InstagramDataResult {
        try await Task.sleep(for:.milliseconds(150))
        switch operation {
        case "feed":
            feedLoads += 1
            if ProcessInfo.processInfo.arguments.contains("--uat-feed-choice") {
                feedPages = 0
                return .init(posts: [.init(id:"1",username:"porch.fixture",caption:"A quiet place to catch up.",timestamp:0,media:[])], hasMore: true)
            }
            if feedLoads > 1 { return .init(error:"offline") }
            return .init(posts:[.init(id:"1",username:"uat.fixture",caption:"Fictional post retained during a failed refresh.",timestamp:1,media:[])])
        case "moreFeed":
            feedPages += 1
            guard ProcessInfo.processInfo.arguments.contains("--uat-feed-choice") else { return .init() }
            // Deliberately larger than the first choice, then a short final page.
            let range = feedPages == 1 ? 2...9 : 10...11
            return .init(posts:range.map { .init(id:String($0),username:"porch.fixture",caption:"Fictional post \($0).",timestamp:0,media:[]) }, hasMore:feedPages == 1)
        case "inbox": return .init(threads:[.init(id:"21",title:"UAT fixture",preview:messages.last?.text ?? "")])
        case "thread":
            if ProcessInfo.processInfo.arguments.contains("--uat-delayed-reconcile"), messages.count > 1, !delayedReconciliation {
                delayedReconciliation = true
                try await Task.sleep(for: .seconds(5))
            }
            return .init(messages:messages)
        case "sendText":
            if ProcessInfo.processInfo.arguments.contains("--uat-delayed-send") {
                try await Task.sleep(for: .seconds(5))
            }
            if ProcessInfo.processInfo.arguments.contains("--uat-blocked") {
                return .init(error:"actionBlocked",diagnostic:["http":"400","reason":"feedback_required"])
            }
            messages.append(.init(id:UUID().uuidString,text:text,mine:true,context:context))
            if ProcessInfo.processInfo.arguments.contains("--uat-unconfirmed") { return .init(error:"sendUnconfirmed") }
            return .init(sentItemID:messages.last?.id)
        default: return .init()
        }
    }
    func close() { }
}
#endif
