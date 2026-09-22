import AppKit
import Combine
import Foundation

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
            if settings.enabledProviders != oldValue.enabledProviders {
                refresh(force: true)
            }
        }
    }

    private let providers: [ProviderID: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .codex: CodexProvider(),
    ]
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isPanelOpen = false
    private var wakeObserver: NSObjectProtocol?

    init() {
        self.settings = Settings.load()
        for provider in ProviderID.allCases {
            states[provider] = .neverRead
        }
        // A Mac that has been asleep comes back with numbers that are hours stale and a
        // timer that did not fire while it slept, so treat waking as a reason to read.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Bind self here rather than inside the Task: a captured weak var cannot be
            // read from concurrently-executing code.
            guard let self else { return }
            Task { @MainActor in self.refresh(force: true) }
        }
        refresh(force: true)
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - When the panel is on screen

    /// The panel is open, so read more often and read now if what we have is stale.
    func panelAppeared() {
        isPanelOpen = true
        refresh()
        scheduleNextRead()
    }

    func panelDisappeared() {
        isPanelOpen = false
        scheduleNextRead()
    }

    // MARK: - Reading

    /// Reads every enabled provider. Without `force`, a read that happened in the last
    /// few seconds counts as good enough, so opening and closing the panel repeatedly
    /// does not spawn a process each time.
    func refresh(force: Bool = false) {
        guard refreshTask == nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < RefreshPolicy.freshEnough {
            return
        }
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
            self?.applyResults(results)
        }
    }

    private func applyResults(_ results: [(ProviderID, ProviderState)]) {
        for (id, state) in results { states[id] = state }
        isRefreshing = false
        lastRefresh = Date()
        refreshTask = nil
        scheduleNextRead()
    }

    /// One-shot rather than repeating, because the gap changes with what we just read.
    private func scheduleNextRead() {
        timer?.invalidate()
        let delay = RefreshPolicy.delay(isPanelOpen: isPanelOpen, resets: knownResets)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh(force: true) }
        }
    }

    /// Every reset time we currently know about, across the providers on show.
    private var knownResets: [Date] {
        visibleProviders
            .compactMap { states[$0]?.snapshot }
            .flatMap { $0.windows }
            .compactMap { $0.resetsAt }
    }

    // MARK: - Preparing

    /// The button is only worth pressing while the 5-hour window is still whole: once the
    /// clock is running, starting it again just spends quota. So it is live only when every
    /// 5-hour bar we can read is at 100%, and only when at least one of them could be read.
    var canPrepare: Bool {
        guard preparing.isEmpty, !visibleProviders.isEmpty else { return false }
        let fiveHourWindows = visibleProviders.compactMap { states[$0]?.snapshot?.window(.fiveHour) }
        guard !fiveHourWindows.isEmpty else { return false }
        return fiveHourWindows.allSatisfy(\.isFull)
    }

    /// Shown on hover, so the button can explain itself without putting a paragraph in the panel.
    var prepareHint: String {
        if !preparing.isEmpty { return "Starting the cooldown…" }
        if visibleProviders.isEmpty { return "No providers are switched on." }
        let fiveHourWindows = visibleProviders.compactMap { states[$0]?.snapshot?.window(.fiveHour) }
        if fiveHourWindows.isEmpty { return "No 5-hour window has been read yet." }
        if !fiveHourWindows.allSatisfy(\.isFull) { return "The 5-hour window is already running." }
        return "Sends one short throwaway prompt now, so the 5-hour clock is already running when you sit down. It shifts the window earlier; it does not add quota."
    }

    /// Runs the prepare command for every enabled provider that has one.
    func prepareAll() {
        guard canPrepare else { return }
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
            self.finishPreparing(provider, outcome: outcome)
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
            self?.refresh(force: true)
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
