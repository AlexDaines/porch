import SwiftUI

// Plural's restraint, reduced further toward Light Phone: quiet, monochrome controls.
enum PorchTheme {
    static let canvas = Color.black
    static let surface = Color(hex: 0x101010)
    static let bone = Color(hex: 0xE9E4D6)
    static let muted = Color(hex: 0x939393)
    static let line = Color(hex: 0x262626)
    static let accent = bone
    static let utility = Font.system(.caption2, design: .monospaced).weight(.semibold)
}
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
struct PorchButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .monospaced).weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(filled ? PorchTheme.canvas : PorchTheme.accent)
            .background(filled ? PorchTheme.accent : PorchTheme.canvas)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(PorchTheme.utility).tracking(1.2).foregroundStyle(PorchTheme.muted)
    }
}
struct Avatar: View {
    let initials: String
    var size: CGFloat = 44
    var story = false
    var body: some View {
        Text(initials).font(.system(size: size * 0.28, weight: .medium, design: .monospaced))
            .foregroundStyle(PorchTheme.bone).frame(width: size, height: size)
            .overlay(Circle().stroke(story ? PorchTheme.accent : PorchTheme.line, lineWidth: 1))
    }
}
struct PorchRule: View {
    var body: some View { Rectangle().fill(PorchTheme.line).frame(height: 1).accessibilityHidden(true) }
}
