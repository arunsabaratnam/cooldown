#!/bin/bash
# Runs Tests/CoreChecks against the real Core sources. Needs only the command line
# tools: there is no XCTest without Xcode, so this compiles the pure files directly.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/core-checks"
swiftc -O \
  Sources/Cooldown/Core/Models.swift \
  Sources/Cooldown/Core/RefreshPolicy.swift \
  Sources/Cooldown/Core/Shell.swift \
  Sources/Cooldown/Core/LoginRunner.swift \
  Tests/CoreChecks/main.swift \
  -o "$OUT"
"$OUT"
