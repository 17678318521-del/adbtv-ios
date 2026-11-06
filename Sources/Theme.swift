import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0xF7FAFF)
    static let card = Color.white
    static let primary = Color(hex: 0xA8D8FF)
    static let primaryDeep = Color(hex: 0x7AB8F0)
    static let primarySoft = Color(hex: 0xEAF4FF)
    static let success = Color(hex: 0x7FD8A6)
    static let warning = Color(hex: 0xFFD166)
    static let danger = Color(hex: 0xFF8A8A)
    static let textMain = Color(hex: 0x1F2937)
    static let textSub = Color(hex: 0x6B7A90)
    static let textFaint = Color(hex: 0x9EB0C8)
    static let divider = Color(hex: 0xE6EEF7)
    static let fieldBorder = Color(hex: 0xDCE7F5)
    static let deepBlue = Color(hex: 0x2A5C8A)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .shadow(color: Theme.primaryDeep.opacity(0.08), radius: 14, x: 0, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(enabled ? Theme.deepBlue : Theme.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? (configuration.isPressed ? Theme.primaryDeep : Theme.primary)
                                  : Theme.primarySoft)
            )
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Theme.deepBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? Theme.primarySoft : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.primary, lineWidth: 1)
                    )
            )
    }
}

struct KeyPadStyle: ButtonStyle {
    var highlight: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: highlight ? .bold : .medium))
            .foregroundColor(highlight ? Theme.deepBlue : Theme.textMain)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(configuration.isPressed ? Theme.primary : (highlight ? Theme.primarySoft : Color.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(highlight ? Theme.primary : Theme.divider, lineWidth: 1)
                    )
            )
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.textSub)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}
