import SwiftUI

// Visual contract (a binding contract, not an AI default):
// - canvas: true black
// - text:   warm off-white (NOT pure #fff)
// - accent: exactly one (warm amber)
struct ContentView: View {
    private enum Palette {
        static let canvas = Color.black
        static let text   = Color(red: 0xE9 / 255, green: 0xE4 / 255, blue: 0xDA / 255)
        static let accent = Color(red: 0xE0 / 255, green: 0xA0 / 255, blue: 0x30 / 255)
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Porch")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Text("new app, ready to iterate")
                    .font(.callout)
                    .foregroundStyle(Palette.accent)
            }
            .padding()
        }
    }
}
