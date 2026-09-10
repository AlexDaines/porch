import SwiftUI

struct WelcomeView: View {
    let connect: () -> Void
    let sample: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Porch").font(PorchTheme.title)
                    .frame(minHeight: 44).padding(.bottom, 16)
                Button(action: connect) {
                    HStack(spacing: 8) { Text("Open Instagram"); Image(systemName: "arrow.right").font(PorchTheme.detail) }
                }.buttonStyle(PorchButtonStyle()).accessibilityIdentifier("connect")
                Button("Sample", action: sample)
                    .font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading).accessibilityIdentifier("sample")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8)
        }
    }
}
