import Foundation

/// A GUI app launched from Finder inherits a bare PATH (`/usr/bin:/bin:/usr/sbin:/sbin`),
/// which is almost never where `claude` or `codex` live. We recover the PATH the user
/// actually has in their terminal by asking their login shell once, and cache it.
final class ShellEnvironment {
    static let shared = ShellEnvironment()

    private let lock = NSLock()
    private var cachedPath: String?

    private init() {}

    var path: String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPath { return cachedPath }
        let resolved = Self.resolveLoginPath()
        cachedPath = resolved
        return resolved
    }

    private static func resolveLoginPath() -> String {
        let fallback = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "\(NSHomeDirectory())/.volta/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return fallback
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let loginPath = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loginPath.isEmpty else { return fallback }
        // Union of both, so a login shell that trims things still leaves us the usual suspects.
        var seen = Set<String>()
        let merged = (loginPath.split(separator: ":") + fallback.split(separator: ":"))
            .map(String.init)
            .filter { seen.insert($0).inserted }
        return merged.joined(separator: ":")
    }

    /// Absolute path of a CLI on the recovered PATH, or nil when it is not installed.
    func locate(_ binary: String) -> String? {
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

private final class OutputBuffer {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }

    var strings: (out: String, err: String) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

enum Shell {
    struct Result {
        let status: Int32
        let out: String
        let err: String
        let timedOut: Bool
        let launchFailure: String?

        var succeeded: Bool { launchFailure == nil && !timedOut && status == 0 }
    }

    /// Runs a command, blocking the calling thread. Never call this on the main thread.
    ///
    /// `timeout` is also the intended lifetime for long-lived servers we talk to over stdio
    /// (Codex's app-server, which never exits on its own): we write the requests, let it run,
    /// then terminate it and parse whatever it wrote. A `timedOut` result is therefore not
    /// automatically a failure — the caller decides.
    static func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval = 20
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ShellEnvironment.shared.path
        // Keep the CLIs from trying to draw a TUI at us.
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let buffer = OutputBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { buffer.appendOut(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { buffer.appendErr(chunk) }
        }

        do {
            try process.run()
        } catch {
            return Result(
                status: -1, out: "", err: "", timedOut: false,
                launchFailure: "could not launch \(executable): \(error.localizedDescription)"
            )
        }

        if let stdin, let data = stdin.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()

        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
            let hardDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < hardDeadline { usleep(50_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()

        // Pick up anything still buffered in the pipes after exit.
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        buffer.appendOut(outPipe.fileHandleForReading.availableData)
        buffer.appendErr(errPipe.fileHandleForReading.availableData)

        let (out, err) = buffer.strings
        return Result(
            status: process.terminationStatus,
            out: out,
            err: err,
            timedOut: timedOut,
            launchFailure: nil
        )
    }
}

extension Shell {
    /// `run` off the main thread.
    static func runAsync(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval = 20
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: run(
                        executable: executable,
                        arguments: arguments,
                        stdin: stdin,
                        timeout: timeout
                    )
                )
            }
        }
    }
}
