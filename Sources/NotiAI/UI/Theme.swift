import SwiftUI

/// Brand colours: deep ink and highlighter yellow. Everything else uses system colours
/// so the app follows light and dark mode.
enum Theme {
    static let ink = Color(red: 0x1B / 255, green: 0x27 / 255, blue: 0x47 / 255)
    static let marker = Color(red: 1.0, green: 0xD8 / 255, blue: 0x4D / 255)
    static let markerNS = NSColor(red: 1.0, green: 0xD8 / 255, blue: 0x4D / 255, alpha: 1)
}

/// A chisel-tip highlighter stroke: slanted ends and a faint wobble, like a real marker.
struct MarkerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let slant = min(6, r.height * 0.25)
        p.move(to: CGPoint(x: r.minX + slant, y: r.minY + 1))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.minY - 1.5))
        p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY - 1))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.maxY + 1.5))
        p.closeSubpath()
        return p
    }
}

/// The primary button: highlighter yellow with ink text in both light and dark mode.
struct MarkerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(MarkerShape().fill(Theme.marker))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
