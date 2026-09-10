import SwiftUI

struct WelcomeView: View {
    @ObservedObject var connection: InstagramConnection
    let sample: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text("Porch").font(PorchTheme.heading).frame(minHeight: 44)
                    Spacer(minLength: 64)
                    VStack(spacing: 16) {
                        if connection.checking {
                            ProgressView().accessibilityLabel("Checking Instagram sign-in")
                            Text("Connecting…").font(PorchTheme.body)
                            Button("Cancel") { connection.cancel() }.buttonStyle(PorchButtonStyle())
                        } else {
                            Button(connection.hasSavedSession ? "Open Porch" : "Sign in to Instagram") {
                                connection.start()
                            }.buttonStyle(PorchButtonStyle()).accessibilityIdentifier("connect")
                            Text(connection.hasSavedSession ? "Your Instagram sign-in is saved." : "Your sign-in stays on this device.")
                                .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                            if let failure = connection.failure {
                                Text(failure).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                                Button("Sign in again") { connection.signIn() }.buttonStyle(PorchButtonStyle())
                            }
                            Button("Try the sample", action: sample)
                                .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                                .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("sample")
                        }
                    }.frame(maxWidth: 320)
                    Spacer(minLength: 64)
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .multilineTextAlignment(.center)
            }.scrollIndicators(.hidden)
        }.task { await connection.refreshSavedSession() }
    }
}
