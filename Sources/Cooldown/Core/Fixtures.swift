#if DEBUG
import Foundation

/// Sample readings for `COOLDOWN_FIXTURE`. See `UsageStore.fixture`.
enum Fixtures {
    static func states(_ name: String, now: Date = Date()) -> [(ProviderID, ProviderState)] {
        func window(_ kind: UsageWindow.Kind, used: Double, resetsIn: TimeInterval?) -> UsageWindow {
            UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
        }
        func claude(fiveHourUsed: Double) -> ProviderState {
            .ok(ProviderSnapshot(provider: .claude, windows: [
                window(.fiveHour, used: fiveHourUsed, resetsIn: fiveHourUsed == 0 ? nil : 3 * 3600 + 12 * 60),
                window(.weekly, used: 36, resetsIn: 2 * 86400 + 12 * 3600),
                window(.weeklySecondary, used: 9, resetsIn: 2 * 86400 + 12 * 3600),
            ], source: "fixture", capturedAt: now))
        }
        func codex(fiveHourUsed: Double) -> ProviderState {
            .ok(ProviderSnapshot(provider: .codex, windows: [
                window(.fiveHour, used: fiveHourUsed, resetsIn: fiveHourUsed == 0 ? nil : 4 * 3600 + 5 * 60),
                window(.weekly, used: 82, resetsIn: 2 * 86400 + 4 * 3600),
            ], source: "fixture", capturedAt: now))
        }
        switch name {
        case "claude": return [(.claude, claude(fiveHourUsed: 0)), (.codex, codex(fiveHourUsed: 36))]
        case "both": return [(.claude, claude(fiveHourUsed: 0)), (.codex, codex(fiveHourUsed: 0))]
        case "none": return [(.claude, claude(fiveHourUsed: 18)), (.codex, codex(fiveHourUsed: 60))]
        case "empty": return [(.claude, .unavailable(reason: "not signed in")), (.codex, .notInstalled)]
        default: return [(.claude, claude(fiveHourUsed: 18)), (.codex, codex(fiveHourUsed: 0))]
        }
    }
}
#endif
