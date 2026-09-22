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
    @Published private(set) var accounts: [AccountID: AccountState] = [:]
    /// Sign-ins in progress, or how the last one failed. Absent when nothing is happening.
    @Published private(set) var logins: [AccountID: LoginProgress] = [:]
    /// Why the numbers on show for a provider are older than the last read: the read failed
    /// for a transient reason and the previous good numbers were kept. Absent when current.
    @Published private(set) var staleReasons: [ProviderID: String] = [:]
    /// Which Settings pane is showing, so the gear menu can open straight to one.
    @Published var settingsPane: SettingsPane = .general
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.enabledProviders != oldValue.enabledProviders {
                refresh(force: true)
            }
            if settings.launchAtLogin != oldValue.launchAtLogin {
                let actual = LoginItem.set(settings.launchAtLogin)
                if actual != settings.launchAtLogin, Self.fixture == nil {
                    // macOS said no; show the switch the way it really is.
                    DispatchQueue.main.async { self.settings.launchAtLogin = actual }
                }
            }
            if settings.notifyOnReset != oldValue.notifyOnReset {
                if settings.notifyOnReset { ResetNotifier.requestPermission() }
                scheduleResetNotifications()
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
    private var loginWatch: Task<Void, Never>?
    private var loginTasks: [AccountID: Task<Void, Never>] = [:]

    private var lastAccountsRefresh: Date?
    /// Reads in a row that came back rate limited, and until when we leave the source alone.
    private var rateLimitedReads = 0
    private var holdOffUntil: Date?

    /// `COOLDOWN_FIXTURE=codex|claude|both|none|empty` swaps the real reads for sample
    /// numbers, so every state of the panel can be looked at on a machine that has only
    /// one of the CLIs, or neither. Debug builds only: a release build never shows a
    /// number it did not read.
    #if DEBUG
    static let fixture = ProcessInfo.processInfo.environment["COOLDOWN_FIXTURE"]
    #else
    static let fixture: String? = nil
    #endif

    init() {
        self.settings = Settings.load()
        for provider in ProviderID.allCases {
            states[provider] = .neverRead
        }
        for account in AccountID.allCases {
            accounts[account] = .unknown
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
        refreshAccounts()
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
        refreshAccounts()
    }

    func panelDisappeared() {
        isPanelOpen = false
        scheduleNextRead()
    }

    // MARK: - Reading

    /// Reads every enabled provider. Without `force`, a read that happened in the last
    /// few seconds counts as good enough, so opening and closing the panel repeatedly
    /// does not spawn a process each time, and a source that has just rate limited us is
    /// left alone until its hold-off is over.
    func refresh(force: Bool = false) {
        guard refreshTask == nil else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < RefreshPolicy.freshEnough {
            return
        }
        if !force, let holdOffUntil, holdOffUntil > Date() {
            return
        }
        #if DEBUG
        if let fixture = Self.fixture {
            for (id, state) in Fixtures.states(fixture) { states[id] = state }
            lastRefresh = Date()
            return
        }
        #endif
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
        let now = Date()
        for (id, fresh) in results {
            let merged = ProviderState.merge(previous: states[id], fresh: fresh, now: now)
            states[id] = merged.state
            staleReasons[id] = merged.staleReason
        }
        if results.contains(where: { $0.1.isRateLimited }) {
            rateLimitedReads += 1
            holdOffUntil = now.addingTimeInterval(RefreshPolicy.holdOff(afterRateLimits: rateLimitedReads))
        } else {
            rateLimitedReads = 0
            holdOffUntil = nil
        }
        isRefreshing = false
        lastRefresh = now
        refreshTask = nil
        scheduleNextRead()
        scheduleResetNotifications()
    }

    /// One-shot rather than repeating, because the gap changes with what we just read.
    private func scheduleNextRead() {
        timer?.invalidate()
        let delay = RefreshPolicy.delay(isPanelOpen: isPanelOpen, resets: knownResets, holdOffUntil: holdOffUntil)
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

    /// A 5-hour window is only worth starting while it is still whole: once its clock is
    /// running, starting it again just spends quota. So the button offers exactly the
    /// providers whose 5-hour window we can read and is at 100%.
    var startableProviders: [ProviderID] {
        visibleProviders.filter { states[$0]?.snapshot?.window(.fiveHour)?.isFull == true }
    }

    var canPrepare: Bool {
        preparing.isEmpty && !startableProviders.isEmpty
    }

    /// "Start Codex cooldown", "Start both cooldowns", or what to say when there is nothing to start.
    var prepareLabel: String {
        if !preparing.isEmpty { return "Starting…" }
        let startable = startableProviders
        switch startable.count {
        case 0:
            let anyRead = visibleProviders.contains { states[$0]?.snapshot?.window(.fiveHour) != nil }
            return anyRead ? "Cooldowns running" : "Start cooldown"
        case 1: return "Start \(startable[0].displayName) cooldown"
        case 2: return "Start both cooldowns"
        default: return "Start all cooldowns"
        }
    }

    /// The one line under the button.
    func prepareNote(now: Date = Date()) -> String {
        let startable = startableProviders
        let endsAt = Format.clockTime(now.addingTimeInterval(5 * 3600))
        switch startable.count {
        case 0:
            if visibleProviders.isEmpty { return "No providers are switched on." }
            let resets = visibleProviders
                .compactMap { states[$0]?.snapshot?.window(.fiveHour)?.resetsAt }
                .filter { $0 > now }
            if let next = resets.min() { return "Next reset at \(Format.clockTime(next))." }
            return "No 5-hour window has been read yet."
        case 1: return "\(startable[0].displayName) resets by \(endsAt) if you start it now."
        case 2: return "Both reset by \(endsAt) if you start them now."
        default: return "They all reset by \(endsAt) if you start them now."
        }
    }

    /// Runs the start command for each provider whose window is full, and no others.
    func prepareAll() {
        guard canPrepare else { return }
        for provider in startableProviders {
            prepare(provider)
        }
    }

    func prepare(_ provider: ProviderID) {
        guard !preparing.contains(provider) else { return }
        preparing.insert(provider)
        if Self.fixture != nil {
            let outcome = PrepareOutcome(provider: provider, succeeded: true, detail: "fixture", at: Date())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.finishPreparing(provider, outcome: outcome) }
            return
        }
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

    /// The tightest 5-hour window on show, as a fraction left (0...1), or nil before any read.
    var tightestFiveHourFraction: Double? {
        visibleProviders
            .compactMap { states[$0]?.snapshot?.window(.fiveHour)?.remainingPercent }
            .min()
            .map { min(1, max(0, $0 / 100)) }
    }

    /// Each provider's 5-hour fraction left, for the twin-bar icon.
    var fiveHourFractions: [Double?] {
        visibleProviders.map { provider in
            states[provider]?.snapshot?.window(.fiveHour).map { min(1, max(0, $0.remainingPercent / 100)) }
        }
    }

    /// "Couldn't refresh: …. Showing the numbers from 4m ago." when a provider's numbers
    /// were kept through a failed read, or nil when they are current.
    func staleNote(for provider: ProviderID, now: Date = Date()) -> String? {
        guard let reason = staleReasons[provider], let snapshot = states[provider]?.snapshot else { return nil }
        return "Couldn’t refresh: \(reason). Showing the numbers from \(Format.age(of: snapshot.capturedAt, from: now))."
    }

    /// True when nothing on show could be read at all, which the icon draws as dashed.
    var nothingConnected: Bool {
        !visibleProviders.contains { states[$0]?.snapshot != nil }
    }

    /// The number next to the icon, when the user has asked for one.
    var menuBarTitle: String {
        guard settings.showPercentInMenuBar else { return "" }
        let values = visibleProviders.compactMap { fiveHourValue(for: $0) }
        guard let lowest = values.min() else { return "–" }
        return format(lowest)
    }

    // MARK: - Accounts

    /// Account details barely change, and reading Claude's means starting its CLI, so the
    /// panel opening only re-reads them once a minute. Sign-in and sign-out force it.
    func refreshAccounts(force: Bool = false) {
        if !force, let lastAccountsRefresh, Date().timeIntervalSince(lastAccountsRefresh) < 60 { return }
        lastAccountsRefresh = Date()
        if Self.fixture != nil {
            accounts[.claude] = .signedIn(AccountInfo(email: "you@example.com", plan: "Max"))
            accounts[.codex] = .signedOut
            return
        }
        Task { [weak self] in
            var results: [(AccountID, AccountState)] = []
            await withTaskGroup(of: (AccountID, AccountState).self) { group in
                for account in AccountID.allCases {
                    group.addTask { (account, await Accounts.read(account)) }
                }
                for await result in group { results.append(result) }
            }
            guard let self else { return }
            for (id, state) in results { self.accounts[id] = state }
        }
    }

    /// Runs the provider's own sign-in behind the scenes (installing the tool first if
    /// needed): the browser opens, you approve, and the row flips to signed in.
    func connect(_ account: AccountID) {
        guard loginTasks[account] == nil else { return }
        logins[account] = .starting
        // Bound here rather than inside the Task: a captured weak var cannot be read from
        // concurrently-executing code.
        let onPhase: @Sendable (LoginRunner.Phase) -> Void = { [weak self] phase in
            guard let self else { return }
            Task { @MainActor in self.noteLoginPhase(account, phase) }
        }
        loginTasks[account] = Task { [weak self] in
            let outcome = await Accounts.signIn(account, onPhase: onPhase)
            guard let self else { return }
            self.loginTasks[account] = nil
            if outcome.succeeded {
                self.logins[account] = nil
                self.refreshAccounts(force: true)
                self.refresh(force: true)
            } else if Task.isCancelled {
                self.logins[account] = nil
            } else {
                self.logins[account] = .failed(outcome.detail)
            }
        }
    }

    private func noteLoginPhase(_ account: AccountID, _ phase: LoginRunner.Phase) {
        guard loginTasks[account] != nil else { return }
        logins[account] = phase == .waitingBrowser ? .waitingBrowser : .starting
    }

    func cancelConnect(_ account: AccountID) {
        loginTasks[account]?.cancel()
        loginTasks[account] = nil
        logins[account] = nil
    }

    /// The same sign-in in a visible Terminal window, then a watch for it to finish: the
    /// way out when the hidden flow hits something that needs a person at the keyboard.
    func connectInTerminal(_ account: AccountID) {
        cancelConnect(account)
        Accounts.openLogin(account)
        loginWatch?.cancel()
        loginWatch = Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                let state = await Accounts.read(account)
                guard let self else { return }
                self.accounts[account] = state
                if state.isSignedIn {
                    self.refreshAccounts(force: true)
                    self.refresh(force: true)
                    return
                }
            }
        }
    }

    func signOut(_ account: AccountID) {
        cancelConnect(account)
        Task { [weak self] in
            await Accounts.signOut(account)
            guard let self else { return }
            self.refreshAccounts(force: true)
            self.refresh(force: true)
        }
    }

    // MARK: - Notifications

    private func scheduleResetNotifications() {
        guard Self.fixture == nil else { return }
        let resets: [(ProviderID, Date)] = visibleProviders.compactMap { provider in
            guard let window = states[provider]?.snapshot?.window(.fiveHour),
                  let resetsAt = window.resetsAt,
                  !window.isFull
            else { return nil }
            return (provider, resetsAt)
        }
        ResetNotifier.schedule(resets, enabled: settings.notifyOnReset)
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

/// Where a sign-in started from the panel has got to.
enum LoginProgress: Equatable {
    case starting
    case waitingBrowser
    case failed(String)
}
