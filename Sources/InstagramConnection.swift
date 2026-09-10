import Foundation
import Combine

@MainActor
protocol InstagramAuthentication: AnyObject {
    var onPossibleSignIn: (() -> Void)? { get set }
    func hasSavedSession() async -> Bool
    func connect()
    func suspend()
}

// Opening or dismissing a browser never counts as signing in. Only a successful
// authenticated read enters the native app.
@MainActor
final class InstagramConnection: ObservableObject {
    enum Phase { case idle, signingIn, connected }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hasSavedSession = false
    @Published private(set) var checking = false
    @Published private(set) var failure: String?
    private let browser: any InstagramAuthentication
    private let transport: any InstagramTransport
    private var task: Task<Void, Never>?
    private var generation = 0
    private var automaticChecksPaused = false

    init(browser: any InstagramAuthentication, transport: (any InstagramTransport)? = nil) {
        self.browser = browser
        self.transport = transport ?? WebKitInstagramTransport()
        browser.onPossibleSignIn = { [weak self] in self?.checkSignIn(automatic: true) }
    }
    func refreshSavedSession() async {
        let epoch = generation
        let saved = await browser.hasSavedSession()
        if epoch == generation { hasSavedSession = saved }
    }
    func start() {
        guard phase == .idle, !checking else { return }
        if hasSavedSession { verify() } else { signIn() }
    }
    func signIn() {
        cancel()
        phase = .signingIn
        browser.connect()
    }
    func checkSignIn(automatic: Bool = false) {
        guard phase == .signingIn, !checking else { return }
        // Failed automatic checks stop. Cookie churn must not create a retry loop.
        guard !automatic || !automaticChecksPaused else { return }
        verify(automatic: automatic)
    }
    private func verify(automatic: Bool = false) {
        guard !checking else { return }
        checking = true
        failure = nil
        if !automatic { automaticChecksPaused = false }
        let epoch = generation
        task = Task { @MainActor in
            let saved = await browser.hasSavedSession()
            guard epoch == generation else { return }
            hasSavedSession = saved
            if !saved {
                checking = false
                task = nil
                if phase == .idle { signIn() }
                else if !automatic { failure = "Finish signing in with Instagram." }
                return
            }
            let code: String?
            do {
                let result = try await transport.execute("session", identifier: "", text: "", context: "")
                code = result.error
            } catch { code = InstagramDataClient.code(error) }
            guard epoch == generation else { return }
            checking = false
            task = nil
            if let code {
                if code == "signIn" {
                    hasSavedSession = false
                    if phase == .idle { signIn() }
                    else { failure = "Finish signing in with Instagram." }
                } else { failure = Self.message(code); automaticChecksPaused = true }
            } else {
                hasSavedSession = true
                phase = .connected
                transport.close()
                browser.suspend()
            }
        }
    }
    func cancel() {
        generation += 1
        task?.cancel(); task = nil
        transport.close(); browser.suspend()
        checking = false; failure = nil; automaticChecksPaused = false; phase = .idle
    }
    static func message(_ code: String) -> String {
        switch code {
        case "offline": "You're offline. Reconnect and try again."
        case "timedOut": "Instagram took too long to respond. Try again."
        case "rateLimited": "Instagram needs a pause. Try again in a few minutes."
        default: "Couldn't confirm your sign-in. Please try again."
        }
    }
}
