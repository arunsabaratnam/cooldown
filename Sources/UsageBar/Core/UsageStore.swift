import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var preparing: Set<ProviderID> = []
    @Published private(set) var recentOutcomes: [PrepareOutcome] = []
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.refreshIntervalSeconds != oldValue.refreshIntervalSeconds {
                restartTimer()
            }
        }
    }

    private let providers: [ProviderID: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .codex: CodexProvider(),
    ]
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init() {
        self.settings = Settings.load()
        for provider in ProviderID.allCases {
            states[provider] = .neverRead
        }
        restartTimer()
        refresh()
    }

    // MARK: - Reading

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        let selected: [(ProviderID, any UsageProvider)] = ProviderID.allCases
            .filter { settings.enabledProviders.contains($0) }
            .compactMap { id in providers[id].map { (id, $0) } }

        refreshTask = Task { [weak self] in
            var results: [(ProviderID, ProviderState)] = []
            await withTaskGroup(of: (ProviderID, ProviderState).self) { group in
                for (id, provider) in selected {
                    group.addTask { (id, await provider.read()) }
                }
                for await result in group { results.append(result) }
            }
            await self?.applyResults(results)
        }
    }

    private func applyResults(_ results: [(ProviderID, ProviderState)]) {
        for (id, state) in results { states[id] = state }
        isRefreshing = false
        lastRefresh = Date()
        refreshTask = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(30, settings.refreshIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Preparing

    /// Runs the prepare command for every enabled provider that has one.
    func prepareAll() {
        for provider in ProviderID.allCases where settings.enabledProviders.contains(provider) {
            prepare(provider)
        }
    }

    func prepare(_ provider: ProviderID) {
        guard !preparing.contains(provider) else { return }
        preparing.insert(provider)
        let command = settings.prepareCommand(for: provider)
        Task { [weak self] in
            let outcome = await Preparer.prepare(provider: provider, command: command)
            guard let self else { return }
            await self.finishPreparing(provider, outcome: outcome)
        }
    }

    private func finishPreparing(_ provider: ProviderID, outcome: PrepareOutcome) {
        preparing.remove(provider)
        recentOutcomes.removeAll { $0.provider == provider }
        recentOutcomes.append(outcome)
        // The window only shows up in the quota numbers once the server has seen the
        // request, so give it a beat before reading again.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.refresh()
        }
    }

    func outcome(for provider: ProviderID) -> PrepareOutcome? {
        recentOutcomes.first { $0.provider == provider }
    }

    // MARK: - Derived display

    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { settings.enabledProviders.contains($0) }
    }

    /// The text drawn in the menu bar.
    var menuBarTitle: String {
        switch settings.menuBarDisplay {
        case .iconOnly:
            return ""
        case .tightest:
            let values = visibleProviders.compactMap { fiveHourValue(for: $0) }
            guard let lowest = values.min() else { return "–" }
            return format(lowest)
        case .allProviders:
            let parts = visibleProviders.map { provider -> String in
                guard let value = fiveHourValue(for: provider) else {
                    return "\(provider.shortTag) –"
                }
                return "\(provider.shortTag) \(format(value))"
            }
            return parts.isEmpty ? "–" : parts.joined(separator: "  ")
        }
    }

    /// Percent remaining (or used, per settings) in the 5-hour window, when we know it.
    private func fiveHourValue(for provider: ProviderID) -> Double? {
        guard let window = states[provider]?.snapshot?.window(.fiveHour) else { return nil }
        return settings.showRemaining ? window.remainingPercent : window.usedPercent
    }

    private func format(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }
}
