import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Butter {
    static let bgTop = Color(hex: 0x231C13)
    static let bgBottom = Color(hex: 0x17130D)
    static let card = Color.white.opacity(0.055)
    static let stroke = Color(hex: 0xFFE7A8, opacity: 0.10)
    static let text = Color(hex: 0xFFF6E2)
    static let text2 = Color(hex: 0xFFF6E2, opacity: 0.66)
    static let text3 = Color(hex: 0xFFF6E2, opacity: 0.42)
    static let butter = Color(hex: 0xFFD66B)
    static let toast = Color(hex: 0xF4A63A)
    static let green = Color(hex: 0x9AD77F)
    static let blue = Color(hex: 0x7CC6FF)
    static let red = Color(hex: 0xFF7A5C)
    static let track = Color.white.opacity(0.07)

    static func tint(for state: ChargeState) -> Color {
        switch state {
        case .holding, .sailing, .full: return green
        case .discharging, .calibrating: return blue
        case .heat, .unsupported: return red
        case .charging, .topUp: return butter
        case .system, .onBattery: return text2
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Butter.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Butter.stroke))
    }
}

struct PillButtonStyle: ButtonStyle {
    var active = false
    var tint: Color = Butter.butter
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .foregroundStyle(active ? Color.black.opacity(0.85) : Butter.text)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
