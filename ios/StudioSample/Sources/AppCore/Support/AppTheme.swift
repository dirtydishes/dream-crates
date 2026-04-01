import SwiftUI

enum AppThemeOption: String, CaseIterable, Identifiable {
    case allDark = "all-dark"
    case diddyParty = "diddy-party"
    case dirtydishes
    case davyDolla = "davy-dolla"
    case catppuccinLatte = "catppuccin-latte"
    case catppuccinFrappe = "catppuccin-frappe"
    case catppuccinMacchiato = "catppuccin-macchiato"
    case catppuccinMocha = "catppuccin-mocha"
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allDark:
            return "all dark"
        case .diddyParty:
            return "diddy party"
        case .dirtydishes:
            return "dirtydishes"
        case .davyDolla:
            return "Davy Dolla$"
        case .catppuccinLatte:
            return "Catppuccin Latte"
        case .catppuccinFrappe:
            return "Catppuccin Frappe"
        case .catppuccinMacchiato:
            return "Catppuccin Macchiato"
        case .catppuccinMocha:
            return "Catppuccin Mocha"
        case .terminal:
            return "terminal"
        }
    }

    var detail: String {
        switch self {
        case .allDark:
            return "Pure black, white, and hard contrast."
        case .diddyParty:
            return "Simple black on white."
        case .dirtydishes:
            return "Soft lavender with a hazy late-night glow."
        case .davyDolla:
            return "Cash green with restrained editorial type."
        case .catppuccinLatte:
            return "Catppuccin's soft light roast."
        case .catppuccinFrappe:
            return "Catppuccin's cool dusk palette."
        case .catppuccinMacchiato:
            return "Catppuccin with richer midnight contrast."
        case .catppuccinMocha:
            return "Catppuccin's inky flagship dark."
        case .terminal:
            return "CRT green with a bundled Nerd Font."
        }
    }

    var theme: AppTheme {
        switch self {
        case .allDark:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x050505),
                panel: Color(hex: 0x111111),
                cardTop: Color(hex: 0x141414),
                cardBottom: Color(hex: 0x090909),
                accent: Color(hex: 0xF5F5F5),
                accentLabel: Color.black.opacity(0.86),
                label: Color(hex: 0xF7F7F7),
                secondaryLabel: Color(hex: 0xA3A3A3),
                avatarBlend: Color(hex: 0x6B7280),
                typography: AppTypography(
                    displayFamily: .system(design: .default),
                    bodyFamily: .system(design: .default)
                )
            )
        case .diddyParty:
            return AppTheme(
                name: displayName,
                colorScheme: .light,
                bg: Color(hex: 0xFAFAFA),
                panel: Color(hex: 0xF0F0F0),
                cardTop: Color(hex: 0xFFFFFF),
                cardBottom: Color(hex: 0xE8E8E8),
                accent: Color(hex: 0x111111),
                accentLabel: Color.white.opacity(0.95),
                label: Color(hex: 0x121212),
                secondaryLabel: Color(hex: 0x5E5E5E),
                avatarBlend: Color(hex: 0xBDBDBD),
                typography: AppTypography(
                    displayFamily: .system(design: .default),
                    bodyFamily: .system(design: .default)
                )
            )
        case .dirtydishes:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x191420),
                panel: Color(hex: 0x282036),
                cardTop: Color(hex: 0x35264A),
                cardBottom: Color(hex: 0x221A30),
                accent: Color(hex: 0xC8A7FF),
                accentLabel: Color(hex: 0x26183D),
                label: Color(hex: 0xF2ECFF),
                secondaryLabel: Color(hex: 0xB9ABCF),
                avatarBlend: Color(hex: 0xF0C6D8),
                typography: AppTypography(
                    displayFamily: .system(design: .rounded),
                    bodyFamily: .system(design: .rounded)
                )
            )
        case .davyDolla:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x09150C),
                panel: Color(hex: 0x12241A),
                cardTop: Color(hex: 0x1B3425),
                cardBottom: Color(hex: 0x102015),
                accent: Color(hex: 0x94C973),
                accentLabel: Color(hex: 0x142115),
                label: Color(hex: 0xEFF7E9),
                secondaryLabel: Color(hex: 0xB2C7B0),
                avatarBlend: Color(hex: 0xD7CF88),
                typography: AppTypography(
                    displayFamily: .system(design: .serif),
                    bodyFamily: .system(design: .default)
                )
            )
        case .catppuccinLatte:
            return AppTheme(
                name: displayName,
                colorScheme: .light,
                bg: Color(hex: 0xEFF1F5),
                panel: Color(hex: 0xE6E9EF),
                cardTop: Color(hex: 0xDCE0E8),
                cardBottom: Color(hex: 0xCCD0DA),
                accent: Color(hex: 0x8839EF),
                accentLabel: Color.white.opacity(0.95),
                label: Color(hex: 0x4C4F69),
                secondaryLabel: Color(hex: 0x6C6F85),
                avatarBlend: Color(hex: 0xEA76CB),
                typography: AppTypography(
                    displayFamily: .system(design: .rounded),
                    bodyFamily: .system(design: .default)
                )
            )
        case .catppuccinFrappe:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x303446),
                panel: Color(hex: 0x414559),
                cardTop: Color(hex: 0x51576D),
                cardBottom: Color(hex: 0x3C4052),
                accent: Color(hex: 0xCA9EE6),
                accentLabel: Color(hex: 0x292C3C),
                label: Color(hex: 0xC6D0F5),
                secondaryLabel: Color(hex: 0xA5ADCE),
                avatarBlend: Color(hex: 0x81C8BE),
                typography: AppTypography(
                    displayFamily: .system(design: .rounded),
                    bodyFamily: .system(design: .rounded)
                )
            )
        case .catppuccinMacchiato:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x24273A),
                panel: Color(hex: 0x363A4F),
                cardTop: Color(hex: 0x494D64),
                cardBottom: Color(hex: 0x2B3045),
                accent: Color(hex: 0xC6A0F6),
                accentLabel: Color(hex: 0x24273A),
                label: Color(hex: 0xCAD3F5),
                secondaryLabel: Color(hex: 0xA5ADCB),
                avatarBlend: Color(hex: 0x8BD5CA),
                typography: AppTypography(
                    displayFamily: .system(design: .rounded),
                    bodyFamily: .system(design: .default)
                )
            )
        case .catppuccinMocha:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x1E1E2E),
                panel: Color(hex: 0x313244),
                cardTop: Color(hex: 0x45475A),
                cardBottom: Color(hex: 0x24273A),
                accent: Color(hex: 0xCBA6F7),
                accentLabel: Color(hex: 0x1E1E2E),
                label: Color(hex: 0xCDD6F4),
                secondaryLabel: Color(hex: 0xA6ADC8),
                avatarBlend: Color(hex: 0x94E2D5),
                typography: AppTypography(
                    displayFamily: .system(design: .rounded),
                    bodyFamily: .system(design: .rounded)
                )
            )
        case .terminal:
            return AppTheme(
                name: displayName,
                colorScheme: .dark,
                bg: Color(hex: 0x071109),
                panel: Color(hex: 0x0D1B10),
                cardTop: Color(hex: 0x132A17),
                cardBottom: Color(hex: 0x09150C),
                accent: Color(hex: 0x49F15B),
                accentLabel: Color(hex: 0x09120A),
                label: Color(hex: 0xB8F7B1),
                secondaryLabel: Color(hex: 0x6FB46B),
                avatarBlend: Color(hex: 0xD4FF72),
                typography: AppTypography(
                    displayFamily: .custom(
                        regular: "CaskaydiaCoveNFM-Regular",
                        bold: "CaskaydiaCoveNFM-Bold"
                    ),
                    bodyFamily: .custom(
                        regular: "CaskaydiaCoveNFM-Regular",
                        bold: "CaskaydiaCoveNFM-Bold"
                    )
                )
            )
        }
    }
}

struct AppTheme {
    let name: String
    let colorScheme: ColorScheme
    let bg: Color
    let panel: Color
    let cardTop: Color
    let cardBottom: Color
    let accent: Color
    let accentLabel: Color
    let label: Color
    let secondaryLabel: Color
    let avatarBlend: Color
    let typography: AppTypography

    var cardGradient: [Color] { [cardTop, cardBottom] }

    var surfaceFill: Color {
        label.opacity(colorScheme == .dark ? 0.08 : 0.06)
    }

    var chromeStroke: Color {
        label.opacity(colorScheme == .dark ? 0.08 : 0.12)
    }

    var activeStroke: Color {
        accent.opacity(colorScheme == .dark ? 0.72 : 0.78)
    }

    var shadow: Color {
        .black.opacity(colorScheme == .dark ? 0.24 : 0.14)
    }

    var artworkGradient: [Color] {
        let finalColor = colorScheme == .dark ? Color.black.opacity(0.84) : bg
        return [accent.opacity(colorScheme == .dark ? 0.18 : 0.14), panel, finalColor]
    }

    var avatarGradient: [Color] {
        [accent.opacity(0.9), avatarBlend.opacity(0.78)]
    }

    func font(_ style: AppFontStyle, weight: Font.Weight = .regular) -> Font {
        typography.font(style, weight: weight)
    }
}

struct AppTypography {
    let displayFamily: AppFontFamily
    let bodyFamily: AppFontFamily

    func font(_ style: AppFontStyle, weight: Font.Weight = .regular) -> Font {
        let family = style.usesDisplayFamily ? displayFamily : bodyFamily
        return family.font(for: style, weight: weight)
    }
}

enum AppFontStyle {
    case body
    case title2
    case title3
    case headline
    case subheadline
    case caption
    case caption2

    var textStyle: Font.TextStyle {
        switch self {
        case .body:
            return .body
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .subheadline:
            return .subheadline
        case .caption:
            return .caption
        case .caption2:
            return .caption2
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .body:
            return 17
        case .title2:
            return 22
        case .title3:
            return 20
        case .headline:
            return 17
        case .subheadline:
            return 15
        case .caption:
            return 12
        case .caption2:
            return 11
        }
    }

    var usesDisplayFamily: Bool {
        switch self {
        case .title2, .title3, .headline:
            return true
        case .body, .subheadline, .caption, .caption2:
            return false
        }
    }
}

enum AppFontFamily {
    case system(design: Font.Design)
    case custom(regular: String, bold: String)

    func font(for style: AppFontStyle, weight: Font.Weight) -> Font {
        switch self {
        case let .system(design):
            return .system(style.textStyle, design: design, weight: weight)
        case let .custom(regular, bold):
            let fontName = prefersBoldFace(for: weight) ? bold : regular
            return .custom(fontName, size: style.pointSize, relativeTo: style.textStyle)
        }
    }

    private func prefersBoldFace(for weight: Font.Weight) -> Bool {
        switch weight {
        case .semibold, .bold, .heavy, .black:
            return true
        default:
            return false
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppThemeOption.allDark.theme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
