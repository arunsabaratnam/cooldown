#!/bin/bash
# Retakes the pictures in the README from a debug build showing sample numbers.
#
# The app draws its own windows to PNG (see `COOLDOWN_SHOTS` in CooldownApp.swift),
# so this works without granting the terminal screen recording. It briefly resets the
# saved settings so the pictures show the defaults, and puts them back afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUNDLE_ID="com.arunsabaratnam.Cooldown"
STAGE="$(mktemp -d)"
APP="$STAGE/Cooldown.app"
BACKUP="$STAGE/settings.plist"

echo "==> Building (debug)"
swift build
BINARY="$(swift build --show-bin-path)/Cooldown"

mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/Cooldown"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

if pgrep -x Cooldown >/dev/null; then
  echo "error: quit Cooldown first, so the pictures show the sample numbers" >&2
  exit 1
fi

restore() {
  if [ -s "$BACKUP" ]; then
    defaults import "$BUNDLE_ID" "$BACKUP"
  fi
  rm -rf "$STAGE"
}
trap restore EXIT

defaults export "$BUNDLE_ID" "$BACKUP" 2>/dev/null || true
defaults delete "$BUNDLE_ID" CooldownSettings 2>/dev/null || true

echo "==> Drawing"
COOLDOWN_FIXTURE=claude COOLDOWN_SHOTS="$ROOT/assets" "$APP/Contents/MacOS/Cooldown"
ls -1 "$ROOT"/assets/*.png
