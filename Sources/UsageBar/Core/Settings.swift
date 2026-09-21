import Foundation

/// What the menu bar shows when space is tight.
enum MenuBarDisplay: String, CaseIterable, Identifiable, Codable {
    /// "C 62 · X 41" — remaining percent of each provider's 5-hour window.
    case allProviders
    /// "62%" — whichever enabled provider has the least 5-hour quota left.
    case tightest
    /// Icon only.
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allProviders: return "Every provider"
        case .tightest: return "Whichever is lowest"
        case .iconOnly: return "Icon only"
        }
    }
}

struct Settings: Codable, Equatable {
    var enabledProviders: Set<ProviderID> = Set(ProviderID.allCases)
    var menuBarDisplay: MenuBarDisplay = .allProviders
    /// Shown in the menu bar: what is left, rather than what is used.
    var showRemaining: Bool = true
    var prepareCommands: [ProviderID: String] = [
        .claude: #"claude -p "reply with ok""#,
        .codex: #"codex exec "reply with ok""#,
    ]

    static let defaultsKey = "UsageBarSettings"

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
        prepareCommands[provider] ?? Settings().prepareCommands[provider] ?? ""
    }
}
