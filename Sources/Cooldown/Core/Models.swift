import Foundation

/// A coding agent whose quota we can read.
enum ProviderID: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Short tag used in the menu bar, where space is scarce.
    var shortTag: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        }
    }

    /// The CLI we look for to decide whether this provider is installed at all.
    var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }
}

/// One quota window, normalised across providers.
struct UsageWindow: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case fiveHour
        case weekly
        case spend

        var label: String {
            switch self {
            case .fiveHour: return "5-hour"
            case .weekly: return "Weekly"
            case .spend: return "Spend"
            }
        }

        /// Ordering in the menu.
        var rank: Int {
            switch self {
            case .fiveHour: return 0
            case .weekly: return 1
            case .spend: return 2
            }
        }
    }

    let kind: Kind
    /// 0...100, and occasionally above 100 once a limit is exceeded.
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { kind.rawValue }

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    var hasReset: Bool {
        guard let resetsAt else { return false }
        return resetsAt <= Date()
    }

    /// True when the bar is showing the whole window. Rounded the way the panel rounds
    /// it, so "full" always means the same thing to the eye and to the button.
    var isFull: Bool {
        Int(remainingPercent.rounded()) >= 100
    }

    /// How long a window of this kind lasts, where that is fixed.
    var length: TimeInterval? {
        switch kind {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 24 * 3600
        case .spend: return nil
        }
    }

    /// When the running window began, worked back from its reset. Nil when we were not
    /// told a reset time, rather than guessing one.
    var startedAt: Date? {
        guard let resetsAt, let length else { return nil }
        return resetsAt.addingTimeInterval(-length)
    }
}

/// What we managed to read for one provider at one moment.
struct ProviderSnapshot: Equatable {
    let provider: ProviderID
    let windows: [UsageWindow]
    /// Human-readable description of where the numbers came from, shown in the menu
    /// so the numbers are never mistaken for something more authoritative than they are.
    let source: String
    let capturedAt: Date

    func window(_ kind: UsageWindow.Kind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    var sortedWindows: [UsageWindow] {
        windows.sorted { $0.kind.rank < $1.kind.rank }
    }
}

/// The result of a read. `unavailable` carries the reason, which the menu shows verbatim:
/// we never substitute a plausible-looking number for one we could not read.
///
/// `rateLimited` marks a failure the source brought on itself by being asked too often,
/// so the store knows to hold off rather than ask again on the usual cadence.
enum ProviderState: Equatable {
    case notInstalled
    case neverRead
    case unavailable(reason: String, rateLimited: Bool = false)
    case ok(ProviderSnapshot)

    var snapshot: ProviderSnapshot? {
        if case .ok(let snapshot) = self { return snapshot }
        return nil
    }

    var isRateLimited: Bool {
        if case .unavailable(_, let rateLimited) = self { return rateLimited }
        return false
    }

    /// What to show after a read, given what was on show before it.
    ///
    /// Quota only moves when the user actually uses the tool, so numbers read a few minutes
    /// ago are still right when a read fails for a transient reason (a 429, a dropped
    /// connection). Those are kept, with the failure as `staleReason` so the panel can say
    /// so. They are dropped again once one of their windows has reset, because from then on
    /// they would be wrong, and a read that says the tool is gone is never papered over.
    static func merge(
        previous: ProviderState?,
        fresh: ProviderState,
        now: Date
    ) -> (state: ProviderState, staleReason: String?) {
        guard
            case .unavailable(let reason, _) = fresh,
            case .ok(let snapshot)? = previous,
            !snapshot.windows.contains(where: { window in
                window.resetsAt.map { $0 <= now } ?? false
            })
        else { return (fresh, nil) }
        return (previous ?? fresh, reason)
    }
}

struct PrepareOutcome: Equatable, Identifiable {
    let id = UUID()
    let provider: ProviderID
    let succeeded: Bool
    let detail: String
    let at: Date
}
