import Foundation

/// Runs a CLI's browser sign-in (and, when the CLI is missing, its installer first) under a
/// pseudo-terminal, so the tool behaves exactly as it does in Terminal — prints its link and
/// opens the browser itself — while the user sees only the browser tab and one line of
/// status in the panel. The credential is minted and stored by the official tool; we
/// never see it.
///
/// The pseudo-terminal comes from `/usr/bin/script`, which ships with macOS, so there is
/// no forking from inside a GUI process. Prompts that just want Enter are answered for
/// the user; anything else stays visible in the failure message, with the offer to run
/// the same thing in Terminal instead.
enum LoginRunner {
    enum Phase: Equatable {
        case starting
        case waitingBrowser
    }

    struct Outcome: Equatable {
        let succeeded: Bool
        /// Why it did not succeed, in a sentence, with the last thing the tool said.
        let detail: String

        static let ok = Outcome(succeeded: true, detail: "")
    }

    /// Text the CLIs print once sign-in is complete. Exit status 0 counts as well.
    static let signInMarkers = ["Logged in as", "Login successful", "Successfully logged in", "logged in successfully"]

    /// - Parameters:
    ///   - command: the executable and its arguments.
    ///   - successMarkers: output that means "done" even before the process exits.
    ///   - timeout: how long to wait for the whole thing, browser round-trip included.
    static func run(
        command: [String],
        successMarkers: [String] = [],
        timeout: TimeInterval,
        onPhase: @escaping @Sendable (Phase) -> Void = { _ in }
    ) async -> Outcome {
        let session = Session(command: command, successMarkers: successMarkers, timeout: timeout, onPhase: onPhase)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: session.run())
                }
            }
        } onCancel: {
            session.cancel()
        }
    }

    // MARK: - Reading what the tool says

    /// Strips ANSI escapes, carriage returns and other control characters, so markers can
    /// be matched against what the user would have read.
    static func plainText(_ raw: String) -> String {
        var text = raw
        for pattern in [
            "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)",   // OSC (titles, hyperlinks)
            "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",                    // CSI (colours, cursor moves)
            "\u{1B}[@-Z\\\\-_]",                               // two-byte escapes
        ] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return String(text.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || $0.value >= 32 }.map(Character.init))
    }

    static func containsLink(_ text: String) -> Bool {
        text.range(of: "https?://[^\\s]+", options: .regularExpression) != nil
    }

    /// The end of the newest "press Enter" prompt after `offset`, so each one is answered once.
    static func enterPromptEnd(in text: String, after offset: Int) -> Int? {
        guard offset <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: offset)
        guard let range = text.range(
            of: "press (enter|return)",
            options: [.regularExpression, .caseInsensitive],
            range: start..<text.endIndex
        ) else { return nil }
        return text.distance(from: text.startIndex, to: range.upperBound)
    }

    /// The last few non-empty lines, squeezed, for a failure message.
    static func tail(of text: String, lines: Int = 3, maxLength: Int = 240) -> String {
        let kept = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(lines)
            .joined(separator: " · ")
        return kept.count > maxLength ? "…" + kept.suffix(maxLength) : kept
    }

    // MARK: - The process

    private final class Session: @unchecked Sendable {
        private let command: [String]
        private let successMarkers: [String]
        private let timeout: TimeInterval
        private let onPhase: @Sendable (Phase) -> Void

        private let lock = NSLock()
        private var output = Data()
        private var process: Process?
        private var cancelled = false

        init(command: [String], successMarkers: [String], timeout: TimeInterval, onPhase: @escaping @Sendable (Phase) -> Void) {
            self.command = command
            self.successMarkers = successMarkers
            self.timeout = timeout
            self.onPhase = onPhase
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = process
            lock.unlock()
            process?.terminate()
        }

        func run() -> Outcome {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            // `script` gives the tool a real terminal; the `stty` gives that terminal a
            // width, so long sign-in links are not wrapped mid-URL.
            process.arguments = ["-q", "/dev/null", "/bin/sh", "-c", "stty cols 200 rows 50 2>/dev/null; exec \"$@\"", "sh"] + command
            process.currentDirectoryURL = URL(fileURLWithPath: ShellEnvironment.workDirectory)

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ShellEnvironment.shared.path
            environment["TERM"] = "xterm-256color"
            environment["COLUMNS"] = "200"
            environment["LINES"] = "50"
            environment["NO_COLOR"] = "1"
            process.environment = environment

            let outPipe = Pipe()
            let inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe
            process.standardInput = inPipe

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    self?.append(chunk)
                }
            }

            lock.lock()
            let alreadyCancelled = cancelled
            self.process = process
            lock.unlock()
            if alreadyCancelled { return Outcome(succeeded: false, detail: "Cancelled.") }

            onPhase(.starting)
            do {
                try process.run()
            } catch {
                return Outcome(succeeded: false, detail: "Could not start \(command.first ?? "the tool"): \(error.localizedDescription)")
            }

            let deadline = Date().addingTimeInterval(timeout)
            var sawLink = false
            var answeredUpTo = 0
            var sawSuccess = false
            var timedOut = false

            while process.isRunning {
                if Date() >= deadline { timedOut = true; break }
                usleep(100_000)
                let text = plainText(currentOutput())

                if !sawLink, containsLink(text) {
                    sawLink = true
                    onPhase(.waitingBrowser)
                }
                if let end = enterPromptEnd(in: text, after: answeredUpTo) {
                    answeredUpTo = end
                    inPipe.fileHandleForWriting.write(Data("\r".utf8))
                }
                if successMarkers.contains(where: text.contains) {
                    sawSuccess = true
                    // Let the tool finish writing its credential and exit on its own.
                    let grace = Date().addingTimeInterval(3)
                    while process.isRunning && Date() < grace { usleep(100_000) }
                    break
                }
            }

            if process.isRunning {
                process.terminate()
                let hardDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < hardDeadline { usleep(50_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            try? inPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            outPipe.fileHandleForReading.readabilityHandler = nil
            append(outPipe.fileHandleForReading.availableData)

            let said = tail(of: plainText(currentOutput()))
            let saying = said.isEmpty ? "" : " It said: \(said)"

            lock.lock()
            let wasCancelled = cancelled
            lock.unlock()

            if wasCancelled { return Outcome(succeeded: false, detail: "Cancelled.") }
            if sawSuccess || process.terminationStatus == 0 { return .ok }
            if timedOut { return Outcome(succeeded: false, detail: "Timed out waiting for the sign-in to finish.\(saying)") }
            return Outcome(succeeded: false, detail: "\(URL(fileURLWithPath: command.first ?? "").lastPathComponent) stopped with status \(process.terminationStatus).\(saying)")
        }

        private func append(_ data: Data) {
            lock.lock()
            output.append(data)
            lock.unlock()
        }

        private func currentOutput() -> String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: output, as: UTF8.self)
        }
    }
}
