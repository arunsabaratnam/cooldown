import Foundation

/// The glyph drawn in the menu bar.
enum MenuBarIcon: String, CaseIterable, Identifiable, Codable {
    /// One ring that drains as the tightest 5-hour window runs down.
    case ring
    /// One small bar per provider.
    case twinBars

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .twinBars: return "Twin bars"
        }
    }
}

/// Which panel design opens from the menu bar.
enum PanelLayout: String, CaseIterable, Identifiable, Codable {
    /// A big ring for the tightest window, today's 5-hour timeline, then the rest.
    case rings
    /// A card of bars for each provider.
    case classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rings: return "Rings"
        case .classic: return "Classic"
        }
    }

    var blurb: String {
        switch self {
        case .rings: return "Big ring and today’s 5-hour timeline"
        case .classic: return "A card of bars for each provider"
        }
    }
}

enum Density: String, CaseIterable, Identifiable, Codable {
    case comfortable
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }
}

struct Settings: Codable, Equatable {
    var enabledProviders: Set<ProviderID> = Set(ProviderID.allCases)
    /// Shown everywhere: what is left, rather than what is used.
    var showRemaining: Bool = true
    var prepareCommands: [ProviderID: String] = Settings.defaultPrepareCommands

    // Menu bar
    var menuBarIcon: MenuBarIcon = .ring
    /// Off keeps the menu bar to one small icon; the numbers are a click away.
    var showPercentInMenuBar: Bool = false
    /// A template icon follows the menu bar's own colour. Tinted, it takes the theme's
    /// accent instead and stops adapting, which is the trade.
    var tintMenuBarIcon: Bool = false

    // Appearance
    var theme: ThemeID = .glacier
    /// Off by default, so picking a theme always changes what you see.
    var followSystemDarkMode: Bool = false
    var darkTheme: ThemeID = .midnight
    var panelLayout: PanelLayout = .rings
    var density: Density = .comfortable
    /// Below this much left, a window is marked as running low.
    var lowThreshold: Int = 20

    // Cooldown and startup
    var notifyOnReset: Bool = false
    var launchAtLogin: Bool = false

    static let defaultPrepareCommands: [ProviderID: String] = [
        .claude: #"claude -p "reply with ok""#,
        .codex: #"codex exec "reply with ok""#,
    ]

    static let lowThresholdChoices = [10, 20, 30, 40]

    static let defaultsKey = "CooldownSettings"

    init() {}

    // Written by hand so that a key missing from an older save falls back to its default
    // instead of failing the whole decode, which would quietly throw away every setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabledProviders = (try? c.decodeIfPresent(Set<ProviderID>.self, forKey: .enabledProviders)) ?? d.enabledProviders
        showRemaining = (try? c.decodeIfPresent(Bool.self, forKey: .showRemaining)) ?? d.showRemaining
        prepareCommands = (try? c.decodeIfPresent([ProviderID: String].self, forKey: .prepareCommands)) ?? d.prepareCommands
        menuBarIcon = (try? c.decodeIfPresent(MenuBarIcon.self, forKey: .menuBarIcon)) ?? d.menuBarIcon
        showPercentInMenuBar = (try? c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar)) ?? d.showPercentInMenuBar
        tintMenuBarIcon = (try? c.decodeIfPresent(Bool.self, forKey: .tintMenuBarIcon)) ?? d.tintMenuBarIcon
        theme = (try? c.decodeIfPresent(ThemeID.self, forKey: .theme)) ?? d.theme
        followSystemDarkMode = (try? c.decodeIfPresent(Bool.self, forKey: .followSystemDarkMode)) ?? d.followSystemDarkMode
        darkTheme = (try? c.decodeIfPresent(ThemeID.self, forKey: .darkTheme)) ?? d.darkTheme
        panelLayout = (try? c.decodeIfPresent(PanelLayout.self, forKey: .panelLayout)) ?? d.panelLayout
        density = (try? c.decodeIfPresent(Density.self, forKey: .density)) ?? d.density
        lowThreshold = (try? c.decodeIfPresent(Int.self, forKey: .lowThreshold)) ?? d.lowThreshold
        notifyOnReset = (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnReset)) ?? d.notifyOnReset
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin

        // Saves from before the icon-only menu bar had a text mode here. Anything other
        // than "icon only" meant the user wanted a number next to the icon.
        if !c.contains(.showPercentInMenuBar),
           let legacy = try? c.decodeIfPresent(String.self, forKey: .menuBarDisplay) {
            showPercentInMenuBar = legacy != "iconOnly"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabledProviders, forKey: .enabledProviders)
        try c.encode(showRemaining, forKey: .showRemaining)
        try c.encode(prepareCommands, forKey: .prepareCommands)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encode(showPercentInMenuBar, forKey: .showPercentInMenuBar)
        try c.encode(tintMenuBarIcon, forKey: .tintMenuBarIcon)
        try c.encode(theme, forKey: .theme)
        try c.encode(followSystemDarkMode, forKey: .followSystemDarkMode)
        try c.encode(darkTheme, forKey: .darkTheme)
        try c.encode(panelLayout, forKey: .panelLayout)
        try c.encode(density, forKey: .density)
        try c.encode(lowThreshold, forKey: .lowThreshold)
        try c.encode(notifyOnReset, forKey: .notifyOnReset)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
    }

    private enum CodingKeys: String, CodingKey {
        case enabledProviders, showRemaining, prepareCommands
        case menuBarIcon, showPercentInMenuBar, tintMenuBarIcon
        case theme, followSystemDarkMode, darkTheme, panelLayout, density, lowThreshold
        case notifyOnReset, launchAtLogin
        /// Read only, to carry an older save forward.
        case menuBarDisplay
    }

    static func load() -> Settings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func prepareCommand(for provider: ProviderID) -> String {
        prepareCommands[provider] ?? Self.defaultPrepareCommands[provider] ?? ""
    }
}
