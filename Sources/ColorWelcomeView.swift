import SwiftUI

struct ColorWelcomeView: View {
    @Binding var selection: PorchColor
    let continueIntoApp: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Porch").font(.headline).foregroundStyle(selection.color)
                        .frame(minHeight: 44)
                    Spacer(minLength: 64)
                    VStack(alignment: .leading, spacing: 28) {
                        Text("Choose a color.").font(.title.weight(.medium))
                            .accessibilityAddTraits(.isHeader)
                        ColorChoices(selection: $selection)
                    }
                    Spacer(minLength: 80)
                    Button(action: continueIntoApp) {
                        HStack {
                            Text("Continue").font(.system(.body, design: .monospaced).weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(.vertical, 18).contentShape(Rectangle())
                            .overlay(alignment: .bottom) { Rectangle().fill(selection.color).frame(height: 1) }
                    }.buttonStyle(.plain).foregroundStyle(selection.color)
                        .accessibilityIdentifier("color-continue")
                    Text("Change it any time in Settings.")
                        .font(.footnote).foregroundStyle(PorchTheme.muted).padding(.top, 14)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                ForEach(PorchColor.allCases) { choice in
                    Button { selection = choice } label: {
                        Circle().fill(choice.color).frame(width: 36, height: 36)
                            .overlay {
                                if selection == choice {
                                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PorchTheme.canvas)
                                }
                            }
                            .padding(6)
                            .overlay { Circle().stroke(selection == choice ? PorchTheme.bone : .clear, lineWidth: 1) }
                            .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(choice.name)
                        .accessibilityIdentifier("color-\(choice.rawValue)")
                        .accessibilityAddTraits(selection == choice ? .isSelected : [])
                }
            }
            if showsName {
                Text(selection.name).font(.subheadline).foregroundStyle(PorchTheme.muted)
                    .accessibilityIdentifier("selected-color")
            }
        }
    }
}
