import Foundation

/// Reads Codex's 5-hour (primary) and weekly (secondary) quota.
///
/// Two sources, in order:
///
/// 1. `codex app-server`, which speaks JSON-RPC over stdio and answers
///    `account/rateLimits/read` with the live server-side numbers. This is the same
///    data `/status` shows inside Codex.
/// 2. The last `token_count` event in the newest session rollout under
///    `~/.codex/sessions/YYYY/MM/DD/`. Codex writes a `rate_limits` block into every
///    one of those events, so this works with no extra setup, but it is only as fresh
///    as the last time Codex actually talked to the server.
struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex

    func read() async -> ProviderState {
        guard let binary = installedBinaryPath() else { return .notInstalled }

        var reasons: [String] = []

        switch await readFromAppServer(binary: binary) {
        case .success(let snapshot):
            return .ok(snapshot)
        case .failure(let reason):
            reasons.append(reason)
        }

        switch readFromSessionRollouts() {
        case .success(let snapshot):
            return .ok(snapshot)
        case .failure(let reason):
            reasons.append(reason)
        }

        return .unavailable(reason: reasons.joined(separator: "; "))
    }

    private enum ReadResult {
        case success(ProviderSnapshot)
        case failure(String)
    }

    // MARK: - Source 1: the app-server

    private func readFromAppServer(binary: String) async -> ReadResult {
        let lines = await StdioRPC.exchange(
            executable: binary,
            arguments: ["app-server"],
            requests: [
                (
                    delay: 0,
                    payload: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"UsageBar","version":"0.1"}}}"#
                ),
                (
                    delay: 0.3,
                    payload: #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#
                ),
                // The app-server can answer an immediate rate-limit read with an empty
                // body, so we give it a moment to finish coming up first.
                (
                    delay: 0.7,
                    payload: #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#
                ),
            ],
            lifetime: 8
        )

        guard !lines.isEmpty else {
            return .failure("codex app-server produced no output")
        }

        for line in lines.reversed() {
            guard
                let data = line.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data),
                let message = JSONDig.object(parsed)
            else { continue }

            if let error = JSONDig.child(message, ["error"]),
               JSONDig.number(message, ["id"]) == 2 {
                let text = (error["message"] as? String) ?? "unknown error"
                return .failure("codex app-server rejected account/rateLimits/read: \(text)")
            }

            guard JSONDig.number(message, ["id"]) == 2,
                  let result = JSONDig.child(message, ["result"]) else { continue }

            if let snapshot = Self.snapshot(fromRateLimits: result, source: "codex app-server (live)") {
                return .success(snapshot)
            }
            return .failure("codex app-server reported no quota windows")
        }

        return .failure("codex app-server did not answer account/rateLimits/read")
    }

    /// Handles both the app-server's camelCase shape and the session files' snake_case one.
    static func snapshot(fromRateLimits payload: [String: Any], source: String, at reference: Date = Date()) -> ProviderSnapshot? {
        let container = JSONDig.child(payload, ["rateLimits", "rate_limits"]) ?? payload

        let candidates: [(UsageWindow.Kind, [String])] = [
            (.fiveHour, ["primary"]),
            (.weekly, ["secondary"]),
        ]

        var found: [(kind: UsageWindow.Kind, reading: JSONDig.Reading, resetsAt: Date?)] = []
        for (kind, keys) in candidates {
            guard let window = JSONDig.child(container, keys) else { continue }
            guard let used = JSONDig.reading(window, ["usedPercent", "used_percent", "utilization"]) else { continue }

            var resetsAt = JSONDig.date(window, ["resetsAt", "resets_at", "resetAt", "reset_at"])
            if resetsAt == nil,
               let relative = JSONDig.number(window, ["resets_in_seconds", "resetsInSeconds"]) {
                resetsAt = reference.addingTimeInterval(relative)
            }
            found.append((kind, used, resetsAt))
        }

        guard !found.isEmpty else { return nil }

        let normalised = JSONDig.normalisePercentages(found.map { $0.reading })
        let windows = zip(found, normalised).map { entry, percent in
            UsageWindow(kind: entry.kind, usedPercent: percent, resetsAt: entry.resetsAt)
        }

        return ProviderSnapshot(
            provider: .codex,
            windows: windows,
            source: source,
            capturedAt: Date()
        )
    }

    // MARK: - Source 2: session rollouts

    private func readFromSessionRollouts() -> ReadResult {
        let root = "\(NSHomeDirectory())/.codex/sessions"
        guard FileManager.default.fileExists(atPath: root) else {
            return .failure("no ~/.codex/sessions directory")
        }

        let files = Self.recentRolloutFiles(under: root, days: 7)
        guard !files.isEmpty else {
            return .failure("no Codex session files in the last 7 days")
        }

        // Codex rewrites older rollout files, so file modification time is not a reliable
        // guide to which record is newest. We read the candidates and compare the
        // timestamps the records carry themselves.
        var newest: (timestamp: Date, limits: [String: Any])?

        for file in files.prefix(40) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("token_count"), line.contains("rate_limits") else { continue }
                guard
                    let data = line.data(using: .utf8),
                    let parsed = try? JSONSerialization.jsonObject(with: data),
                    let record = JSONDig.object(parsed),
                    let payload = JSONDig.child(record, ["payload"]),
                    (payload["type"] as? String) == "token_count",
                    let limits = JSONDig.child(payload, ["rate_limits"])
                else { continue }

                let timestamp = JSONDig.date(record, ["timestamp", "ts"]) ?? Date.distantPast
                if newest == nil || timestamp > newest!.timestamp {
                    newest = (timestamp, limits)
                }
            }
        }

        guard let newest else {
            return .failure("no Codex session recorded a rate limit yet")
        }

        guard var snapshot = Self.snapshot(
            fromRateLimits: newest.limits,
            source: "Codex session log",
            at: newest.timestamp
        ) else {
            return .failure("Codex session log had no readable quota windows")
        }

        snapshot = ProviderSnapshot(
            provider: snapshot.provider,
            windows: snapshot.windows.filter { !$0.hasReset },
            source: snapshot.source,
            capturedAt: newest.timestamp
        )

        guard !snapshot.windows.isEmpty else {
            return .failure("the last Codex session's quota windows have already reset")
        }
        return .success(snapshot)
    }

    static func recentRolloutFiles(under root: String, days: Int, now: Date = Date()) -> [URL] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"

        var urls: [URL] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let directory = URL(fileURLWithPath: "\(root)/\(formatter.string(from: day))")
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            urls.append(contentsOf: entries.filter { $0.pathExtension == "jsonl" })
        }

        return urls.sorted { left, right in
            let leftDate = FileDates.modified(left) ?? .distantPast
            let rightDate = FileDates.modified(right) ?? .distantPast
            return leftDate > rightDate
        }
    }
}

/// A one-shot conversation with a stdio JSON-RPC server that never exits on its own:
/// write the requests on a schedule, collect stdout, then shut it down.
enum StdioRPC {
    static func exchange(
        executable: String,
        arguments: [String],
        requests: [(delay: TimeInterval, payload: String)],
        lifetime: TimeInterval
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: run(
                        executable: executable,
                        arguments: arguments,
                        requests: requests,
                        lifetime: lifetime
                    )
                )
            }
        }
    }

    private static func run(
        executable: String,
        arguments: [String],
        requests: [(delay: TimeInterval, payload: String)],
        lifetime: TimeInterval
    ) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ShellEnvironment.shared.path
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = inPipe

        let lock = NSLock()
        var collected = Data()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                lock.lock(); collected.append(chunk); lock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            return []
        }

        var elapsed: TimeInterval = 0
        for request in requests {
            if request.delay > elapsed {
                Thread.sleep(forTimeInterval: request.delay - elapsed)
                elapsed = request.delay
            }
            guard process.isRunning, let data = (request.payload + "\n").data(using: .utf8) else { break }
            inPipe.fileHandleForWriting.write(data)
        }

        let deadline = Date().addingTimeInterval(max(0, lifetime - elapsed))
        while process.isRunning && Date() < deadline {
            usleep(100_000)
            lock.lock()
            let text = String(decoding: collected, as: UTF8.self)
            let sawResponse = text.contains("\"id\":2") || text.contains("\"id\": 2")
            lock.unlock()
            if sawResponse { break }
        }

        try? inPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let hardDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < hardDeadline { usleep(50_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        collected.append(outPipe.fileHandleForReading.availableData)
        let text = String(decoding: collected, as: UTF8.self)
        lock.unlock()

        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
