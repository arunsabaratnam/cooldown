// Checks for the pure parts of Core, run by scripts/check-core.sh. There is no XCTest
// without Xcode, so this compiles the real source files with a tiny harness instead.
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        print("  ok   \(name)")
    } else {
        failures += 1
        print("  FAIL \(name)  (\(file):\(line))")
    }
}

let now = Date()

final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [LoginRunner.Phase] = []
    func add(_ phase: LoginRunner.Phase) { lock.lock(); phases.append(phase); lock.unlock() }
    var seen: [LoginRunner.Phase] { lock.lock(); defer { lock.unlock() }; return phases }
}

func snapshot(resetsIn seconds: TimeInterval) -> ProviderSnapshot {
    ProviderSnapshot(
        provider: .claude,
        windows: [UsageWindow(kind: .fiveHour, usedPercent: 40, resetsAt: now.addingTimeInterval(seconds))],
        source: "check",
        capturedAt: now.addingTimeInterval(-120)
    )
}

print("RefreshPolicy.holdOff")
check(RefreshPolicy.holdOff(afterRateLimits: 0) == 0, "no hold-off before any rate limit")
check(RefreshPolicy.holdOff(afterRateLimits: 1) == 60, "first rate limit holds off a minute")
check(RefreshPolicy.holdOff(afterRateLimits: 2) == 120, "second doubles it")
check(RefreshPolicy.holdOff(afterRateLimits: 3) == 240, "third doubles again")
check(RefreshPolicy.holdOff(afterRateLimits: 10) == RefreshPolicy.holdOffCap, "capped")
check(RefreshPolicy.holdOffCap <= 15 * 60, "cap is at most 15 minutes")

print("RefreshPolicy.delay with a hold-off")
let inHoldOff = RefreshPolicy.delay(isPanelOpen: true, resets: [], holdOffUntil: now.addingTimeInterval(500), now: now)
check(abs(inHoldOff - 500) < 0.001, "never lands inside the hold-off")
let pastHoldOff = RefreshPolicy.delay(isPanelOpen: true, resets: [], holdOffUntil: now.addingTimeInterval(-1), now: now)
check(pastHoldOff == RefreshPolicy.whileOpen, "an expired hold-off changes nothing")
let noHoldOff = RefreshPolicy.delay(isPanelOpen: false, resets: [], holdOffUntil: nil, now: now)
check(noHoldOff == RefreshPolicy.whileIdle, "no hold-off changes nothing")

print("ShellEnvironment.mergedPath")
check(ShellEnvironment.mergedPath(["/a", "/b", "/a", "", "/c"]) == "/a:/b:/c", "keeps each directory once, in order, and drops empties")
check(ShellEnvironment.mergedPath([]) == "", "empty in, empty out")

print("ShellEnvironment.withoutProtectedFolders")
let home = "/Users/me"
check(
    ShellEnvironment.withoutProtectedFolders(
        ["/Users/me/.local/bin", "/Users/me/Documents/sdk/bin", "/opt/homebrew/bin", "/Users/me/Desktop", "/Users/me/Downloads/x", "/Users/me/Pictures/y", "/Users/me/Music/z", "/Users/me/Movies/w", "/Users/me/Documentsx/bin"],
        home: home
    ) == ["/Users/me/.local/bin", "/opt/homebrew/bin", "/Users/me/Documentsx/bin"],
    "drops every entry inside a folder macOS asks about, and only those"
)
check(ShellEnvironment.withoutProtectedFolders(["/Users/other/Documents/bin"], home: home) == ["/Users/other/Documents/bin"], "another user's folders are left alone")

print("ShellEnvironment.childEnvironment")
let child = ShellEnvironment.childEnvironment(
    inheriting: ["PWD": "/Users/me/Documents/proj", "OLDPWD": "/Users/me/Desktop", "PATH": "/stale", "HOME": "/Users/me"],
    path: "/fresh",
    workDirectory: "/work"
)
check(child["PWD"] == "/work", "PWD is the work folder, not wherever the app was launched from")
check(child["OLDPWD"] == nil, "OLDPWD is dropped")
check(child["PATH"] == "/fresh", "PATH is the recovered one")
check(child["HOME"] == "/Users/me", "everything else is inherited")
check(child["TERM"] == "dumb" && child["NO_COLOR"] == "1", "no TUI, no colour")

print("ShellEnvironment.markAsRepository")
let repoDir = FileManager.default.temporaryDirectory.appendingPathComponent("cooldown-repo-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
ShellEnvironment.markAsRepository(repoDir.path)
ShellEnvironment.markAsRepository(repoDir.path)
var isDir: ObjCBool = false
check(FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git/objects").path, isDirectory: &isDir) && isDir.boolValue, "has an objects folder")
check(FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git/refs").path, isDirectory: &isDir) && isDir.boolValue, "has a refs folder")
check((try? String(contentsOf: repoDir.appendingPathComponent(".git/HEAD"), encoding: .utf8)) == "ref: refs/heads/main\n", "HEAD points at main, and marking twice is harmless")
try? FileManager.default.removeItem(at: repoDir)

print("Settings.prepareCommand")
var settings = Settings()
check(settings.prepareCommand(for: .codex).contains("--skip-git-repo-check"), "the Codex default skips the git repo check")
check(settings.prepareCommand(for: .codex).contains("-m gpt-6-luna") && settings.prepareCommand(for: .codex).contains("model_reasoning_effort=low"), "the Codex default asks for the light model at low reasoning")
check(settings.prepareCommand(for: .claude).contains("--model haiku"), "the Claude default asks for Haiku")
settings.prepareCommands[.codex] = #"codex exec "reply with ok""#
check(settings.prepareCommand(for: .codex) == Settings.defaultPrepareCommands[.codex], "an older default saved to disk reads as the current one")
settings.prepareCommands[.codex] = #"codex exec --skip-git-repo-check "reply with ok""#
check(settings.prepareCommand(for: .codex) == Settings.defaultPrepareCommands[.codex], "so does the default before the model was chosen")
settings.prepareCommands[.claude] = #"claude -p "reply with ok""#
check(settings.prepareCommand(for: .claude) == Settings.defaultPrepareCommands[.claude], "the old Claude default reads as the current one too")
settings.prepareCommands[.codex] = "codex exec --model o3 hi"
check(settings.prepareCommand(for: .codex) == "codex exec --model o3 hi", "a hand-edited command is left alone")

print("ProviderState.merge")
let good = ProviderState.ok(snapshot(resetsIn: 3600))
let limited = ProviderState.unavailable(reason: "usage endpoint returned 429", rateLimited: true)

let kept = ProviderState.merge(previous: good, fresh: limited, now: now)
check(kept.state == good, "a transient failure keeps the last good numbers")
check(kept.staleReason == "usage endpoint returned 429", "and remembers why they are stale")

let fresh = ProviderState.ok(snapshot(resetsIn: 7200))
let replaced = ProviderState.merge(previous: good, fresh: fresh, now: now)
check(replaced.state == fresh, "a success replaces them")
check(replaced.staleReason == nil, "and clears the stale reason")

let expired = ProviderState.merge(previous: .ok(snapshot(resetsIn: -1)), fresh: limited, now: now)
check(expired.state == limited, "old numbers are dropped once their window has reset")
check(expired.staleReason == nil, "with no stale reason")

let plain = ProviderState.unavailable(reason: "no token")
check(ProviderState.merge(previous: .neverRead, fresh: plain, now: now).state == plain, "a failure with nothing to keep shows as is")
check(ProviderState.merge(previous: nil, fresh: plain, now: now).state == plain, "also from a nil previous")
check(ProviderState.merge(previous: good, fresh: .notInstalled, now: now).state == .notInstalled, "not installed is never papered over")

print("ProviderState.isRateLimited")
check(limited.isRateLimited, "rate limited failure is flagged")
check(!plain.isRateLimited, "plain failure is not")
check(!good.isRateLimited, "success is not")

print("LoginRunner text helpers")
let noisy = "\u{1B}[1;32m✓\u{1B}[0m Logged in as\r\n \u{1B}]8;;https://x\u{07}link\u{1B}]8;;\u{07}"
check(LoginRunner.plainText(noisy) == "✓ Logged in as\n link", "strips colours, hyperlinks and carriage returns")
check(LoginRunner.containsLink("open https://claude.ai/oauth/authorize?x=1 now"), "spots a link")
check(!LoginRunner.containsLink("no link here"), "and only a link")
let prompt = "Press Enter to open the browser\n...\npress ENTER again"
let first = LoginRunner.enterPromptEnd(in: prompt, after: 0)
check(first == 11, "finds the first Enter prompt")
check(LoginRunner.enterPromptEnd(in: prompt, after: first ?? 0) == prompt.count - " again".count, "then the next one only")
check(LoginRunner.enterPromptEnd(in: prompt, after: prompt.count) == nil, "and nothing past the end")
check(LoginRunner.tail(of: "a\n\n  b  \nc\nd\n") == "b · c · d", "tail keeps the last three lines")

print("LoginRunner end to end, against fake CLIs under the pseudo-terminal")
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cooldown-checks-\(getpid())")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
func fake(_ name: String, _ body: String) -> String {
    let url = dir.appendingPathComponent(name)
    try! ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}
let happy = fake("happy", """
if [ -t 1 ]; then echo "tty ok"; else echo "no tty"; exit 9; fi
printf 'Press Enter to open the browser: '
read line
echo "Browser did not open? Use https://example.com/oauth/authorize?state=abc"
sleep 1
echo "Logged in as you@example.com"
exit 0
""")
let phases = PhaseLog()
let happyOutcome = await LoginRunner.run(command: [happy], successMarkers: LoginRunner.signInMarkers, timeout: 20) { phases.add($0) }
check(happyOutcome.succeeded, "a sign-in that asks for Enter, prints a link and confirms succeeds: \(happyOutcome.detail)")
check(phases.seen == [.starting, .waitingBrowser], "and reports starting then waiting for the browser: \(phases.seen)")

let sad = fake("sad", "echo 'first line'; echo 'Error: could not reach auth server'; exit 3\n")
let sadOutcome = await LoginRunner.run(command: [sad], successMarkers: LoginRunner.signInMarkers, timeout: 20)
check(!sadOutcome.succeeded, "a failing sign-in fails")
check(sadOutcome.detail.contains("status 3") && sadOutcome.detail.contains("could not reach auth server"), "with the status and what it said: \(sadOutcome.detail)")

let slow = fake("slow", "echo 'waiting forever'; sleep 30\n")
let slowStart = Date()
let slowOutcome = await LoginRunner.run(command: [slow], timeout: 2)
check(!slowOutcome.succeeded && slowOutcome.detail.hasPrefix("Timed out"), "a stuck sign-in times out: \(slowOutcome.detail)")
check(Date().timeIntervalSince(slowStart) < 6, "promptly")

let cancelTask = Task { await LoginRunner.run(command: [slow], timeout: 30) }
try? await Task.sleep(nanoseconds: 500_000_000)
cancelTask.cancel()
let cancelStart = Date()
let cancelled = await cancelTask.value
check(!cancelled.succeeded && cancelled.detail == "Cancelled.", "cancelling stops it: \(cancelled.detail)")
check(Date().timeIntervalSince(cancelStart) < 3, "without waiting for the timeout")
try? FileManager.default.removeItem(at: dir)

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
