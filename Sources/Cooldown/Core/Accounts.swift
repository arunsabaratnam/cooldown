import AppKit
import Foundation

/// An account shown in Settings → Accounts. ChatGPT is listed on its own because that
/// is how people think of it, but it is the same sign-in Codex uses: Codex logs in with
/// a ChatGPT account, and that is the only ChatGPT sign-in Cooldown can see.
enum AccountID: String, CaseIterable, Identifiable {
    case claude, codex, chatgpt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .chatgpt: return "ChatGPT"
        }
    }

    /// The CLI that owns this account's sign-in.
    var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex, .chatgpt: return "codex"
        }
    }

    /// The usage provider this account feeds, if any.
    var provider: ProviderID? {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .chatgpt: return nil
        }
    }

    var loginArguments: [String] {
        switch self {
        case .claude: return ["auth", "login"]
        case .codex, .chatgpt: return ["login"]
        }
    }

    var logoutArguments: [String] {
        switch self {
        case .claude: return ["auth", "logout"]
        case .codex, .chatgpt: return ["logout"]
        }
    }
}

struct AccountInfo: Equatable {
    var email: String?
    var plan: String?

    /// "you@example.com · Max", or whichever half we have.
    var summary: String? {
        let parts = [email, plan].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum AccountState: Equatable {
    case unknown
    case notInstalled
    case signedOut
    case signedIn(AccountInfo)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

enum Accounts {
    static func read(_ account: AccountID) async -> AccountState {
        guard let binary = ShellEnvironment.shared.locate(account.binaryName) else {
            return .notInstalled
        }
        switch account {
        case .claude: return await readClaude(binary: binary)
        case .codex, .chatgpt: return readCodex()
        }
    }

    // MARK: - Claude

    /// `claude auth status --json` answers with `loggedIn`, `email` and `subscriptionType`.
    private static func readClaude(binary: String) async -> AccountState {
        let result = await Shell.runAsync(executable: binary, arguments: ["auth", "status", "--json"], timeout: 15)
        guard
            let data = result.out.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let root = JSONDig.object(parsed)
        else { return .unknown }
        guard (root["loggedIn"] as? Bool) == true else { return .signedOut }
        let email = root["email"] as? String
        let plan = (root["subscriptionType"] as? String).map(planName)
        return .signedIn(AccountInfo(email: email, plan: plan))
    }

    // MARK: - Codex / ChatGPT

    /// Codex keeps its sign-in in `auth.json`. With a ChatGPT login, the `id_token` in there
    /// is a JWT whose claims carry the email and the ChatGPT plan. We only read those two
    /// claims; nothing is sent anywhere.
    private static func readCodex() -> AccountState {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
        let url = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        guard
            let data = try? Data(contentsOf: url),
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let root = JSONDig.object(parsed)
        else { return .signedOut }

        let tokens = JSONDig.object(root["tokens"])
        if let idToken = tokens?["id_token"] as? String, let claims = jwtClaims(idToken) {
            let auth = JSONDig.object(claims["https://api.openai.com/auth"])
            let email = claims["email"] as? String
            let plan = (auth?["chatgpt_plan_type"] as? String).map(planName)
            return .signedIn(AccountInfo(email: email, plan: plan))
        }
        if let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return .signedIn(AccountInfo(email: nil, plan: "API key"))
        }
        return .signedOut
    }

    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard
            let data = Data(base64Encoded: payload),
            let parsed = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return JSONDig.object(parsed)
    }

    /// "max" → "Max", "plus" → "Plus".
    static func planName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Signing in and out

    /// Signing in is the provider's own browser flow, which needs a terminal to run in, so
    /// we hand it to Terminal rather than pretending to do it silently.
    static func openLogin(_ account: AccountID) {
        guard let binary = ShellEnvironment.shared.locate(account.binaryName) else { return }
        let command = ([binary] + account.loginArguments).map(shellQuote).joined(separator: " ")
        let script = """
        #!/bin/zsh -l
        clear
        echo "Signing in to \(account.displayName) for Cooldown…"
        echo
        \(command)
        echo
        echo "Done. You can close this window."
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cooldown-\(account.rawValue)-login.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func signOut(_ account: AccountID) async {
        guard let binary = ShellEnvironment.shared.locate(account.binaryName) else { return }
        _ = await Shell.runAsync(executable: binary, arguments: account.logoutArguments, timeout: 20)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
