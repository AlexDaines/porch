import SwiftUI

struct ColorWelcomeView: View {
    @Binding var selection: PorchColor
    let continueIntoApp: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Porch").font(PorchTheme.utility).foregroundStyle(PorchTheme.muted)
                        .frame(minHeight: 44)
                    Spacer(minLength: 64)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Choose a color.").font(PorchTheme.title)
                            .accessibilityAddTraits(.isHeader)
                        ColorChoices(selection: $selection)
                        Button(action: continueIntoApp) {
                            HStack(spacing: 8) {
                                Text("Continue")
                                Image(systemName: "arrow.right").font(PorchTheme.detail)
                            }.contentShape(Rectangle())
                        }.buttonStyle(PorchButtonStyle())
                            .accessibilityIdentifier("color-continue")
                    }
                    Spacer(minLength: 64)
                }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
            }.scrollIndicators(.hidden)
        }.accessibilityIdentifier("color-welcome")
    }
}

struct ColorChoices: View {
    @Binding var selection: PorchColor
    var showsName = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(PorchColor.allCases) { choice in
                    Button { selection = choice } label: {
                        Rectangle().fill(choice.color).frame(width: 20, height: 20)
                            .overlay {
                                if selection == choice {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
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
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
