import SwiftUI

struct LoadFailure: View {
    let code: String
    let retry: () -> Void
    var actionTitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.message(code)).font(.subheadline).foregroundStyle(PorchTheme.muted)
            Button(actionTitle ?? (code == "signIn" ? "SIGN IN" : "TRY AGAIN"), action: retry)
                .font(PorchTheme.utility).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .accessibilityIdentifier("load-error")
    }
    static func message(_ code: String) -> String {
        switch code {
        case "offline": "You're offline. Connect and try again."
        case "timedOut": "Instagram took too long to respond."
        case "signIn": "Sign in to Instagram to continue."
        case "rateLimited": "Instagram asked us to wait. Try again in a little while."
        case "unsupported": "Instagram returned a view Porch couldn't read."
        case "invalidMessage": "Enter a message of up to 1,000 characters."
        case "sendRejected": "Instagram didn't accept this message. Your draft is still here."
        case "sendUnconfirmed": "Sending wasn't confirmed. The message may have arrived. Check the conversation before sending again."
        default: "Couldn't load this view. Try again."
        }
    }
}
