import SwiftUI

// Horse Weapons structure from Plural, with a personal accent chosen at first launch.
enum PorchTheme {
    static let canvas = Color.black
    static let surface = Color(hex: 0x101010)
    static let bone = Color(hex: 0xE9E4D6)
    static let muted = Color(hex: 0x8A8375)
    static let line = Color(hex: 0x26231F)
    // Minimal chrome must not mean miniature reading text. All styles scale with Dynamic Type.
    static let heading = Font.system(.title2).weight(.medium)
    static let title = Font.system(.body).weight(.medium)
    static let body = Font.system(.body)
    static let detail = Font.system(.subheadline)
    static let utility = Font.system(.subheadline, design: .monospaced)
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
        #if BLIND_UI_FIXTURE
        return BlindUIRuntime.shared?.defaults ?? UserDefaults(suiteName: "porch.blind-ui.invalid")!
        #else
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--appearance-fixture") {
            let name = "porch.appearance-fixture"
            let store = UserDefaults(suiteName: name)!
            if ProcessInfo.processInfo.arguments.contains("--reset-appearance") { store.removePersistentDomain(forName: name) }
            return store
        }
        #endif
        return .standard
        #endif
    }()
    static var bypassIntro: Bool {
        #if BLIND_UI_FIXTURE
        return true
        #else
        #if DEBUG
        return ["--sample", "--native", "--sign-in"].contains { ProcessInfo.processInfo.arguments.contains($0) }
        #else
        return false
        #endif
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
            .frame(minWidth: 44, minHeight: 44)
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
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 32
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

struct PorchSheetHeader: View {
    let title: String
    var closeLabel = "Close"
    var closeDisabled = false
    var identifier = "sheet-title"
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            Text(title).font(PorchTheme.title).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
            Button(action: close) {
                Image(systemName: "xmark").font(PorchTheme.body).frame(width: 44, height: 44)
            }.accessibilityLabel(closeLabel).disabled(closeDisabled)
        }.padding(.horizontal, 12).padding(.vertical, 4)
    }
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
        VStack(spacing: 8) {
            Text(title).font(PorchTheme.title).accessibilityAddTraits(.isHeader)
            Text(message).font(PorchTheme.detail).foregroundStyle(PorchTheme.muted)
            ViewThatFits(in: .horizontal) {
                HStack { actions }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 0) { actions }
            }
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }
    @ViewBuilder private var actions: some View {
        Button(actionTitle, role: destructive ? .destructive : nil, action: confirm)
            .foregroundStyle(accent).frame(minWidth: 44, minHeight: 44).fixedSize(horizontal: false, vertical: true)
        Button("Cancel", action: cancel).foregroundStyle(PorchTheme.muted)
            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 12)
    }
}
