import SwiftUI

struct ColorWelcomeView: View {
    @Binding var selection: PorchColor
    let continueIntoApp: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text("Porch").font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                        .frame(minHeight: 44)
                    Spacer(minLength: 64)
                    VStack(spacing: 20) {
                        Text("Choose a color.").font(PorchTheme.heading)
                            .accessibilityAddTraits(.isHeader)
                        ColorChoices(selection: $selection)
                        Button("Continue", action: continueIntoApp).buttonStyle(PorchButtonStyle())
                            .accessibilityIdentifier("color-continue")
                    }
                    Spacer(minLength: 64)
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .multilineTextAlignment(.center)
            }.scrollIndicators(.hidden)
        }.accessibilityIdentifier("color-welcome")
    }
}

struct ColorChoices: View {
    @Binding var selection: PorchColor
    var showsName = true
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(PorchColor.allCases) { choice in
                    Button { selection = choice } label: {
                        Rectangle().fill(choice.color).frame(width: 28, height: 28)
                            .overlay {
                                if selection == choice {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(PorchTheme.canvas)
                                }
                            }
                            .padding(4)
                            .overlay { Rectangle().stroke(selection == choice ? PorchTheme.bone : .clear, lineWidth: 1) }
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(choice.name)
                        .accessibilityIdentifier("color-\(choice.rawValue)")
                        .accessibilityAddTraits(selection == choice ? .isSelected : [])
                }
            }
            if showsName {
                Text(selection.name).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
                    .accessibilityIdentifier("selected-color")
            }
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }
}
