import SwiftUI

// Horse Weapons structure from Plural, with a personal accent chosen at first launch.
enum PorchTheme {
    static let canvas = Color.black
    static let surface = Color(hex: 0x101010)
    static let bone = Color(hex: 0xE9E4D6)
    static let muted = Color(hex: 0x8A8375)
    static let line = Color(hex: 0x26231F)
    // Native text styles keep the smaller default scale responsive to Dynamic Type.
    static let title = Font.system(.footnote).weight(.medium)
    static let body = Font.system(.footnote)
    static let detail = Font.system(.caption)
    static let utility = Font.system(.caption2, design: .monospaced)
}

enum PorchColor: String, CaseIterable, Identifiable {
    case sage, sea, mist, lilac, sand
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var hex: UInt32 {
        switch self {
        case .sage: 0xA6B8A0
        case .sea: 0x94B8B1
        case .mist: 0x9FB7C7
        case .lilac: 0xB5ADC6
        case .sand: 0xC6BDAA
        }
    }
    var color: Color { Color(hex: hex) }
}

private struct PorchAccentKey: EnvironmentKey {
    static let defaultValue = PorchColor.sage.color
}
extension EnvironmentValues {
    var porchAccent: Color {
        get { self[PorchAccentKey.self] }
        set { self[PorchAccentKey.self] = newValue }
    }
}

enum AppearancePreferences {
    static let store: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--appearance-fixture") {
            let name = "porch.appearance-fixture"
            let store = UserDefaults(suiteName: name)!
            if ProcessInfo.processInfo.arguments.contains("--reset-appearance") { store.removePersistentDomain(forName: name) }
            return store
        }
        #endif
        return .standard
    }()
    static var bypassIntro: Bool {
        #if DEBUG
        return ["--sample", "--native", "--sign-in"].contains { ProcessInfo.processInfo.arguments.contains($0) }
        #else
        return false
        #endif
    }
}
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
struct PorchButtonStyle: ButtonStyle {
    @Environment(\.porchAccent) private var accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(PorchTheme.body)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(accent)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(PorchTheme.utility).tracking(0.4).foregroundStyle(PorchTheme.muted)
    }
}
struct Avatar: View {
    let initials: String
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 28
    var story = false
    var body: some View {
        Text(initials).font(PorchTheme.utility)
            .foregroundStyle(PorchTheme.bone).frame(width: size, height: size)
            .overlay(Rectangle().stroke(story ? PorchTheme.muted : PorchTheme.line, lineWidth: 1))
    }
}
struct PorchRule: View {
    var body: some View { Rectangle().fill(PorchTheme.line).frame(height: 1).accessibilityHidden(true) }
}

extension View {
    func porchSheet() -> some View {
        self.presentationCornerRadius(0)
            .presentationDragIndicator(.hidden)
            .presentationBackground(PorchTheme.canvas)
            .preferredColorScheme(.dark)
            .font(PorchTheme.body)
            .buttonStyle(.plain)
    }
}

struct PorchConfirmation: View {
    @Environment(\.porchAccent) private var accent
    let title: String
    let message: String
    let actionTitle: String
    var destructive = false
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(PorchTheme.title).accessibilityAddTraits(.isHeader)
            Text(message).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
            ViewThatFits(in: .horizontal) {
                HStack { actions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 0) { actions }
            }
        }
    }
    @ViewBuilder private var actions: some View {
        Button(actionTitle, role: destructive ? .destructive : nil, action: confirm)
            .foregroundStyle(accent).frame(minWidth: 44, minHeight: 44, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        Button("Cancel", action: cancel).foregroundStyle(PorchTheme.muted)
            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 12)
    }
}
