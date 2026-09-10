import SwiftUI

struct WelcomeView: View {
    let connect: () -> Void
    let sample: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("Porch").font(.headline); Spacer() }
                    .frame(height: 44).padding(.bottom, 28)
                Button(action: connect) {
                    HStack { Text("Open Instagram"); Spacer(); Image(systemName: "arrow.right") }.padding(.horizontal, 16)
                }.buttonStyle(PorchButtonStyle()).accessibilityIdentifier("connect")
                Text("An independent, experimental Instagram client.")
                    .font(.footnote).foregroundStyle(PorchTheme.muted).padding(.top, 12)
                Button("Sample", action: sample)
                    .font(.subheadline).foregroundStyle(PorchTheme.muted)
                    .frame(minHeight: 44, alignment: .leading).padding(.top, 18).accessibilityIdentifier("sample")
            }.padding(.horizontal, 20).padding(.top, 8)
        }
    }
}
