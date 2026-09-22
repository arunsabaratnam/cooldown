import Foundation

/// The "prepare" action: send one throwaway prompt to each provider now, so the
/// rolling 5-hour window starts counting down before you sit down to work.
///
/// This shifts the window earlier; it does not grant extra quota, and it has no effect
/// on the weekly window, which is a fixed weekly slot. It also spends a small amount of
/// quota — enough to start the clock, which is the point.
enum Preparer {
    static func prepare(provider: ProviderID, command: String) async -> PrepareOutcome {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PrepareOutcome(
                provider: provider,
                succeeded: false,
                detail: "no command configured",
                at: Date()
            )
        }

        // From the home folder, not wherever Finder launched the app from (usually `/`),
        // so the CLIs see the same place a fresh Terminal window would.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = await Shell.runAsync(
            executable: shell,
            arguments: ["-l", "-c", trimmed],
            timeout: 120,
            currentDirectory: NSHomeDirectory()
        )

        if let failure = result.launchFailure {
            return PrepareOutcome(provider: provider, succeeded: false, detail: failure, at: Date())
        }
        if result.timedOut {
            return PrepareOutcome(
                provider: provider,
                succeeded: false,
                detail: "timed out after 2 minutes",
                at: Date()
            )
        }
        if result.status != 0 {
            return PrepareOutcome(
                provider: provider,
                succeeded: false,
                detail: summarise(result.err.isEmpty ? result.out : result.err),
                at: Date()
            )
        }
        return PrepareOutcome(
            provider: provider,
            succeeded: true,
            detail: summarise(result.out),
            at: Date()
        )
    }

    private static func summarise(_ text: String) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .last
            .map(String.init) ?? ""
        if cleaned.isEmpty { return "no output" }
        return cleaned.count > 140 ? String(cleaned.prefix(140)) + "…" : cleaned
    }
}
