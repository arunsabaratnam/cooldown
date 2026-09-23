import AppKit
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
        process.currentDirectoryURL = URL(fileURLWithPath: workDirectory)
        // The cached path does not exist yet; this shell starts from the bare one and
        // reads its profile to fill it in.
        process.environment = childEnvironment(path: fallback)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var loginPath = ""
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            loginPath = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // No login shell to ask; the fallback below is all we have.
        }
        // Union of both, so a login shell that trims things still leaves us the usual
        // suspects, then the app bundles last, so a real install always wins over one.
        let loginEntries = loginPath.isEmpty ? [] : loginPath.split(separator: ":").map(String.init)
        let entries = loginEntries + fallback.split(separator: ":").map(String.init) + bundledCLIDirectories()
        return mergedPath(withoutProtectedFolders(entries, home: NSHomeDirectory()))
    }

    /// The folders macOS guards with a "Cooldown would like to access…" dialog. A PATH
    /// entry inside one (a Flutter SDK kept in ~/Documents, say) is dropped, because a
    /// shell looking for a command it cannot find opens every PATH folder, and each of
    /// these it opens is a dialog.
    static let protectedFolders = ["Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]

    static func withoutProtectedFolders(_ entries: [String], home: String) -> [String] {
        let roots = protectedFolders.map { "\(home)/\($0)" }
        return entries.filter { entry in
            !roots.contains { entry == $0 || entry.hasPrefix($0 + "/") }
        }
    }

    /// The environment every process the app starts gets. Everything is inherited except
    /// what would point a child at the wrong folder: the app launched from a terminal
    /// inherits that terminal's PWD, and zsh checks that folder as it starts, which is a
    /// dialog when it was ~/Documents/something.
    static func childEnvironment(
        inheriting base: [String: String] = ProcessInfo.processInfo.environment,
        path: String? = nil,
        workDirectory: String = ShellEnvironment.workDirectory
    ) -> [String: String] {
        var environment = base
        environment["PATH"] = path ?? ShellEnvironment.shared.path
        environment["PWD"] = workDirectory
        environment.removeValue(forKey: "OLDPWD")
        // Keep the CLIs from trying to draw a TUI at us.
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// An empty folder of our own, where every CLI the app starts is started. They read
    /// whatever folder they start in for project context, so they cannot start where
    /// Finder put the app (the root of the disk), and starting them in the home folder
    /// had Codex walk into ~/Music and ~/Documents, which made macOS ask whether Cooldown
    /// may read Apple Music and Documents.
    ///
    /// The folder is also its own (empty) git repository. Claude and Codex both run git
    /// where they start, and git looks upward for the nearest repository: when the home
    /// folder is one (people keep dotfiles that way), `git status` from anywhere under it
    /// walks all of home, and macOS asks about Photos, Music, Desktop and Downloads in
    /// turn. A repository right here is where that search stops.
    static let workDirectory: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Cooldown/work", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        markAsRepository(directory.path)
        return directory.path
    }()

    /// Lays down the least git needs to call a folder a repository: a HEAD, an objects
    /// folder and a refs folder. Written by hand rather than with `git init`, so it works
    /// on a Mac with no git installed and never triggers the "install the command line
    /// tools?" dialog that /usr/bin/git puts up. Harmless to repeat.
    static func markAsRepository(_ directory: String) {
        let git = URL(fileURLWithPath: directory).appendingPathComponent(".git", isDirectory: true)
        let files = FileManager.default
        for name in ["objects", "refs"] {
            try? files.createDirectory(at: git.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let head = git.appendingPathComponent("HEAD")
        if !files.fileExists(atPath: head.path) {
            try? "ref: refs/heads/main\n".write(to: head, atomically: true, encoding: .utf8)
        }
    }

    /// The entries in order, each kept the first time it appears.
    static func mergedPath(_ entries: [String]) -> String {
        var seen = Set<String>()
        return entries.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// Absolute path of a CLI on the recovered PATH, or nil when it is not installed
    /// anywhere we know to look.
    func locate(_ binary: String) -> String? {
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Some CLIs ship inside a desktop app, for people who use the app and never installed
    /// the CLI on its own. The ChatGPT app carries a full `codex` that reads the same
    /// `~/.codex` sign-in, so it answers `app-server` just as the standalone one does.
    ///
    /// These go on the PATH itself rather than being a private fallback for `locate`, so
    /// every process the app starts can find them too. The start command runs in the
    /// user's login shell, and `codex exec …` there was failing with "command not found"
    /// on a Mac whose only codex was the one inside ChatGPT.app.
    private static func bundledCLIDirectories() -> [String] {
        let apps: [(bundleID: String, fallbackPath: String, relative: String, binary: String)] = [
            ("com.openai.chat", "/Applications/ChatGPT.app", "Contents/Resources", "codex"),
            ("com.openai.codex", "/Applications/Codex.app", "Contents/Resources", "codex"),
        ]
        return apps.flatMap { app -> [String] in
            let located = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path
            return [located, app.fallbackPath].compactMap { $0 }
                .map { "\($0)/\(app.relative)" }
                .filter { FileManager.default.isExecutableFile(atPath: "\($0)/\(app.binary)") }
        }
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
        process.currentDirectoryURL = URL(fileURLWithPath: ShellEnvironment.workDirectory)
        process.environment = ShellEnvironment.childEnvironment()

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
