import SwiftUI

enum ThemeID: String, CaseIterable, Identifiable, Codable {
    case glacier, ember, matcha, midnight, dusk, mono

    var id: String { rawValue }

    var theme: Theme {
        switch self {
        case .glacier:
            return Theme(id: self, name: "Glacier", isDark: false,
                         background: 0xFFFFFF, card: 0xF4F4F6, text: 0x1D1D1F, secondary: 0x6E6E73,
                         accent: 0x13A3B5, button: 0x0B7F8F, track: 0xE2E2E7, hero: 0xEEF7F8, heroText: 0x245A61)
        case .ember:
            return Theme(id: self, name: "Ember", isDark: false,
                         background: 0xFFFAF4, card: 0xF6EBDF, text: 0x2A1D14, secondary: 0x7A6352,
                         accent: 0xE2711D, button: 0xB3500E, track: 0xEAD9C8, hero: 0xFBEBDC, heroText: 0x7A3A0C)
        case .matcha:
            return Theme(id: self, name: "Matcha", isDark: false,
                         background: 0xF8FAF4, card: 0xECF1E4, text: 0x1C2616, secondary: 0x5D6C53,
                         accent: 0x5A9A3C, button: 0x3D7624, track: 0xD9E3CC, hero: 0xE6EFDB, heroText: 0x2F5A1C)
        case .midnight:
            return Theme(id: self, name: "Midnight", isDark: true,
                         background: 0x14161C, card: 0x1F232C, text: 0xEEF0F5, secondary: 0x9AA1B0,
                         accent: 0x7C9CFF, button: 0x4263EB, track: 0x2D323E, hero: 0x1C2336, heroText: 0xB8C6FF)
        case .dusk:
            return Theme(id: self, name: "Dusk", isDark: true,
                         background: 0x1B1624, card: 0x271F34, text: 0xF3EEFA, secondary: 0xA99CBD,
                         accent: 0xC084FC, button: 0x9333EA, track: 0x382D4A, hero: 0x2A1E3B, heroText: 0xDDC2FB)
        case .mono:
            return Theme(id: self, name: "Mono", isDark: false,
                         background: 0xFFFFFF, card: 0xF2F2F2, text: 0x111111, secondary: 0x5F5F5F,
                         accent: 0x111111, button: 0x111111, track: 0xDEDEDE, hero: 0xF2F2F2, heroText: 0x333333)
        }
    }
}

/// One colourway. Warnings (amber, red) are deliberately not part of a theme, so
/// "running low" reads the same whichever one is picked.
struct Theme: Equatable {
    let id: ThemeID
    let name: String
    let isDark: Bool
    let background: Color
    let card: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let button: Color
    let track: Color
    let hero: Color
    let heroText: Color

    init(id: ThemeID, name: String, isDark: Bool,
         background: UInt32, card: UInt32, text: UInt32, secondary: UInt32,
         accent: UInt32, button: UInt32, track: UInt32, hero: UInt32, heroText: UInt32) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.background = Color(hex: background)
        self.card = Color(hex: card)
        self.text = Color(hex: text)
        self.secondary = Color(hex: secondary)
        self.accent = Color(hex: accent)
        self.button = Color(hex: button)
        self.track = Color(hex: track)
        self.hero = Color(hex: hero)
        self.heroText = Color(hex: heroText)
    }

    static let warning = Color(hex: 0xE8930C)
    static let warningText = Color(hex: 0x9A5B00)
    static let warningFill = Color(hex: 0xFDF0D9)
    static let critical = Color(hex: 0xE5484D)

    /// Healthy windows take the theme's accent; low and nearly-gone ones do not.
    func tint(forRemaining remaining: Double, lowThreshold: Int) -> Color {
        if remaining <= 10 { return Self.critical }
        if remaining <= Double(lowThreshold) { return Self.warning }
        return accent
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeID.glacier.theme
}

private struct DensityKey: EnvironmentKey {
    static let defaultValue = Density.comfortable
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    var density: Density {
        get { self[DensityKey.self] }
        set { self[DensityKey.self] = newValue }
    }
}

extension Settings {
    /// The theme to draw with right now, given whether macOS is in dark mode.
    func activeTheme(systemIsDark: Bool) -> Theme {
        (followSystemDarkMode && systemIsDark ? darkTheme : theme).theme
    }
}
