import Foundation

/// Reads Claude Code's 5-hour and weekly quota.
///
/// Two sources, in order:
///
/// 1. `GET https://api.anthropic.com/api/oauth/usage` with the OAuth token Claude Code
///    already holds. This is the live, server-side number — the same thing `/usage` shows.
///    It is undocumented, so it is treated as a best effort and can stop working.
/// 2. The snapshot written by the status line wrapper in `scripts/install-claude-statusline.sh`.
///    Claude Code passes `rate_limits` to the status line command on stdin, which *is*
///    documented, but it only runs while a session is open, so this source goes stale
///    between sessions. We show its age rather than pretending it is live.
struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude

    static let statusLineCachePath = "\(NSHomeDirectory())/.usagebar/claude-statusline.json"

    func read() async -> ProviderState {
        guard installedBinaryPath() != nil else { return .notInstalled }

        var reasons: [String] = []

        if let token = await OAuthToken.load() {
            switch await readFromUsageAPI(token: token) {
            case .success(let snapshot):
                return .ok(snapshot)
            case .failure(let reason):
                reasons.append(reason)
            }
        } else {
            reasons.append("no Claude Code OAuth token found (Keychain or ~/.claude/.credentials.json)")
        }

        if let snapshot = readFromStatusLineCache() {
            return .ok(snapshot)
        }
        reasons.append("no status line snapshot yet — run scripts/install-claude-statusline.sh")

        return .unavailable(reason: reasons.joined(separator: "; "))
    }

    // MARK: - Source 1: the usage endpoint

    private enum ReadResult {
        case success(ProviderSnapshot)
        case failure(String)
    }

    private func readFromUsageAPI(token: String) async -> ReadResult {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return .failure("bad usage URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure("usage endpoint unreachable: \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                return .failure("usage endpoint rejected the token (\(http.statusCode)) — sign in to Claude Code again")
            }
            return .failure("usage endpoint returned \(http.statusCode)")
        }

        guard
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let root = JSONDig.object(parsed)
        else {
            return .failure("usage endpoint returned something that is not JSON")
        }

        guard let snapshot = Self.snapshot(fromUsagePayload: root, source: "usage endpoint (live)") else {
            return .failure("usage endpoint reported no quota windows — this account may not be on a Pro or Max plan")
        }
        return .success(snapshot)
    }

    /// Exposed for the parsing tests.
    static func snapshot(fromUsagePayload root: [String: Any], source: String) -> ProviderSnapshot? {
        // The windows may sit at the top level or under a `usage`/`rate_limits` wrapper.
        let container = JSONDig.child(root, ["rate_limits", "rateLimits", "usage"]) ?? root

        let candidates: [(UsageWindow.Kind, [String])] = [
            (.fiveHour, ["five_hour", "fiveHour", "5h"]),
            (.weekly, ["seven_day", "sevenDay", "seven_day_sonnet", "week", "7d"]),
            (.weeklySecondary, ["seven_day_opus", "sevenDayOpus", "seven_day_large"]),
            (.spend, ["spend_limit", "spendLimit"]),
        ]

        var found: [(kind: UsageWindow.Kind, reading: JSONDig.Reading, resetsAt: Date?)] = []
        for (kind, keys) in candidates {
            guard let window = JSONDig.child(container, keys) else { continue }
            // Unambiguous percent spellings first; `utilization` is the one whose scale
            // we have to infer, so it is the last resort.
            guard let used = JSONDig.reading(window, [
                "used_percentage", "usedPercentage", "used_percent", "usedPercent", "utilization",
            ]) else { continue }
            let resetsAt = JSONDig.date(window, ["resets_at", "resetsAt", "reset_at", "resetAt"])
            found.append((kind, used, resetsAt))
        }

        guard !found.isEmpty else { return nil }

        let normalised = JSONDig.normalisePercentages(found.map { $0.reading })
        let windows = zip(found, normalised).map { entry, percent in
            UsageWindow(kind: entry.kind, usedPercent: percent, resetsAt: entry.resetsAt)
        }

        let live = windows.filter { !$0.hasReset }
        guard !live.isEmpty else { return nil }

        return ProviderSnapshot(
            provider: .claude,
            windows: live,
            source: source,
            capturedAt: Date()
        )
    }

    // MARK: - Source 2: the status line snapshot

    private func readFromStatusLineCache() -> ProviderSnapshot? {
        let url = URL(fileURLWithPath: Self.statusLineCachePath)
        guard
            let data = try? Data(contentsOf: url),
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let root = JSONDig.object(parsed)
        else { return nil }

        let capturedAt = FileDates.modified(url) ?? Date()

        guard var snapshot = Self.snapshot(
            fromUsagePayload: root,
            source: "Claude Code status line"
        ) else { return nil }

        snapshot = ProviderSnapshot(
            provider: snapshot.provider,
            windows: snapshot.windows,
            source: snapshot.source,
            capturedAt: capturedAt
        )
        return snapshot
    }
}

/// Claude Code keeps its OAuth token in the login Keychain on macOS, and in a dotfile
/// on other platforms / older installs. We try both.
private enum OAuthToken {
    static func load() async -> String? {
        if let token = await fromKeychain() { return token }
        return fromCredentialsFile()
    }

    private static func fromKeychain() async -> String? {
        let result = await Shell.runAsync(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 10
        )
        guard result.succeeded else { return nil }
        return extract(fromCredentialsJSON: result.out)
    }

    private static func fromCredentialsFile() -> String? {
        let path = "\(NSHomeDirectory())/.claude/.credentials.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return extract(fromCredentialsJSON: String(decoding: data, as: UTF8.self))
    }

    static func extract(fromCredentialsJSON text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = trimmed.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let root = JSONDig.object(parsed)
        else { return nil }

        let oauth = JSONDig.child(root, ["claudeAiOauth", "claude_ai_oauth", "oauth"]) ?? root
        for key in ["accessToken", "access_token"] {
            if let token = oauth[key] as? String, !token.isEmpty { return token }
        }
        return nil
    }
}
