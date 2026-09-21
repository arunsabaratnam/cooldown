#!/bin/bash
# Builds UsageBar.app. Needs the Xcode command line tools (`xcode-select --install`)
# on macOS 14 or later; no Xcode project and no Xcode app required.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/UsageBar.app"

echo "==> Building"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/UsageBar"
if [ ! -x "$BINARY" ]; then
  echo "error: expected a binary at $BINARY" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/UsageBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The iconset is committed, so this only needs iconutil, which ships with macOS.
# scripts/make-icon.py regenerates the PNGs if the design changes.
if [ -d "$ROOT/Resources/AppIcon.iconset" ]; then
  echo "==> Icon"
  iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature. Enough to launch locally; it is not a distributable signature,
# and macOS will still treat the app as unidentified if you move it between machines.
echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null

echo
echo "Built: $APP"
echo "Run it:      open '$APP'"
echo "Install it:  cp -R '$APP' /Applications/"
