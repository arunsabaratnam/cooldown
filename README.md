# UsageBar

A macOS menu bar app that shows how much of your Claude and Codex quota is left, and
starts the 5-hour window early so it has already been counting down by the time you
sit down to work.

Nothing here is an official integration with either tool. Everything it shows is read
from what the two CLIs already keep on your machine.

## What it shows

Per provider, whichever windows that provider reports:

| | 5-hour | Weekly |
|---|---|---|
| **Claude** | yes | yes (plus a separate window for the largest model, when the account has one) |
| **Codex** | yes (`primary`) | yes (`secondary`) |

Each window shows how much is left, a bar, and when it resets. When a number cannot be
read, the app says why instead of showing a zero — an empty gauge is useful, a wrong one
is not.

## Where the numbers come from

Neither tool publishes a supported "read my quota" API, so each provider has a live
source and a fallback.

**Claude**

1. `GET https://api.anthropic.com/api/oauth/usage`, with the OAuth token Claude Code
   already holds (login Keychain, item `Claude Code-credentials`, falling back to
   `~/.claude/.credentials.json`) and the header `anthropic-beta: oauth-2025-04-20`.
   This is the live server-side number — the same thing `/usage` shows. It is
   undocumented and can change or stop working.
2. The payload Claude Code passes to your status line command, which
   [does document](https://code.claude.com/docs/en/statusline) a `rate_limits` object
   with `five_hour` and `seven_day`, each carrying `used_percentage` and `resets_at`.
   `scripts/install-claude-statusline.sh` installs a wrapper that saves that payload to
   `~/.usagebar/claude-statusline.json` and then hands off to whatever status line you
   already had. This only updates while a session is open, so the app shows its age.

`rate_limits` is only populated for Pro and Max accounts, and only after the first API
response in a session.

**Codex**

1. `codex app-server`, which speaks JSON-RPC over stdio and answers
   `account/rateLimits/read` with `rateLimits.primary` and `rateLimits.secondary`, each
   carrying `usedPercent`, `windowDurationMins` and `resetsAt`. This is the same data
   `/status` shows inside Codex.
2. The last `token_count` event in the newest session rollout under
   `~/.codex/sessions/YYYY/MM/DD/*.jsonl`, which carries a `rate_limits` block with
   `used_percent`, `window_minutes` and `resets_in_seconds`. No setup needed, but it is
   only as fresh as the last time Codex talked to the server. Codex rewrites older
   rollout files, so the app compares the timestamps inside the records rather than
   trusting file modification times.

Run `scripts/probe.sh` to see which of these four answer on your machine. It reads
only; it sends no prompts and changes no files.

## The prepare button

"Start the 5-hour window" sends one short throwaway prompt to each enabled provider
right now, in your login shell:

```
claude -p "reply with ok"
codex exec "reply with ok"
```

Both commands are editable in settings.

The 5-hour window is a rolling one that starts at your first message, so starting it at
9am means it resets at 2pm — which is the point. It shifts the window earlier. It does
not grant extra quota, and it has no effect on the weekly window, which is a fixed
weekly slot. It also spends a small amount of quota, which is unavoidable: starting the
clock means putting something on it.

## Building

Needs macOS 14 or later and the Xcode command line tools (`xcode-select --install`).
There is no Xcode project; it builds with SwiftPM.

```
./scripts/build-app.sh
open build/UsageBar.app
```

The build script assembles `build/UsageBar.app` and signs it ad-hoc, which is enough to
run it on the machine that built it. Copy it to `/Applications` to keep it.

It is a menu bar app (`LSUIElement`), so it has no Dock icon and no window. Quit it from
the menu.

The first read may bring up a Keychain prompt, because reading the Claude Code OAuth
token is exactly the kind of thing macOS asks about. Allow it once.

## Layout

```
Sources/UsageBar/
  UsageBarApp.swift        the menu bar scene and its label
  Core/Models.swift        UsageWindow, ProviderSnapshot, ProviderState
  Core/UsageStore.swift    polling, the prepare action, what the menu bar says
  Core/Settings.swift      what is on, how often, what the prepare commands are
  Core/Preparer.swift      runs a prepare command and reports what happened
  Core/Shell.swift         process runner, and recovering the login PATH
  Core/JSONDig.swift       tolerant JSON reading, because the field spellings vary
  Providers/               one file per provider, each with its live source and fallback
  UI/                      the menu contents
scripts/
  build-app.sh             build and bundle
  probe.sh                 check which quota sources answer on this machine
  install-claude-statusline.sh   install Claude's fallback source
```

## Known gaps

- Not built or run yet: it was written in a Linux container with no Swift toolchain and
  no macOS, so the first `./scripts/build-app.sh` is also the first compile.
- The scale of the usage endpoint's `utilization` field is not documented. The app reads
  unambiguous `*_percentage` spellings as 0–100 and infers the scale only for
  `utilization`; `probe.sh` prints the raw payload so it can be pinned down.
- No launch-at-login yet.
- Only Claude and Codex. Adding another means one file conforming to `UsageProvider`.
