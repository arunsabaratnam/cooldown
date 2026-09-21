#!/bin/bash
# Installs the fallback quota source for Claude.
#
# Claude Code hands its status line command a JSON blob on stdin that includes
# `rate_limits`. This installs a wrapper that saves that blob to
# ~/.usagebar/claude-statusline.json and then hands off to whatever status line
# you already had, so your status line keeps looking the same.
#
# This source only updates while a Claude Code session is open, so it is a fallback:
# the app prefers the live usage endpoint and shows the age of whatever it used.
set -euo pipefail

CACHE_DIR="$HOME/.usagebar"
WRAPPER="$CACHE_DIR/claude-statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$CACHE_DIR"

EXISTING=$(python3 - "$SETTINGS" <<'PY'
import json, sys, os
path = sys.argv[1]
if not os.path.exists(path):
    print(""); raise SystemExit
try:
    settings = json.load(open(path))
except Exception:
    print(""); raise SystemExit
line = settings.get("statusLine") or {}
command = line.get("command", "")
# Don't chain to ourselves if this script has already been run.
print("" if "claude-statusline.sh" in command else command)
PY
)

cat > "$WRAPPER" <<WRAP
#!/bin/bash
# Written by UsageBar. Saves Claude Code's status line payload, then renders a line.
INPUT=\$(cat)
printf '%s' "\$INPUT" > "$CACHE_DIR/claude-statusline.json.tmp"
mv "$CACHE_DIR/claude-statusline.json.tmp" "$CACHE_DIR/claude-statusline.json"
PREVIOUS=$(printf '%q' "$EXISTING")
if [ -n "\$PREVIOUS" ]; then
  printf '%s' "\$INPUT" | eval "\$PREVIOUS"
else
  printf '%s' "\$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit
model = (data.get("model") or {}).get("display_name", "")
limits = data.get("rate_limits") or {}
parts = [p for p in [model] if p]
for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
    window = limits.get(key) or {}
    used = window.get("used_percentage")
    if used is not None:
        parts.append("%s %d%% left" % (label, max(0, round(100 - used))))
print(" · ".join(parts))
'
fi
WRAP
chmod +x "$WRAPPER"

python3 - "$SETTINGS" "$WRAPPER" <<'PY'
import json, os, shutil, sys
path, wrapper = sys.argv[1], sys.argv[2]
os.makedirs(os.path.dirname(path), exist_ok=True)
settings = {}
if os.path.exists(path):
    shutil.copyfile(path, path + ".usagebar-backup")
    try:
        settings = json.load(open(path))
    except Exception:
        settings = {}
settings["statusLine"] = {"type": "command", "command": wrapper}
with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
print("updated " + path + (" (previous version saved alongside as .usagebar-backup)" if os.path.exists(path + ".usagebar-backup") else ""))
PY

echo "Installed $WRAPPER"
echo "Open a Claude Code session and send one message; the snapshot appears at $CACHE_DIR/claude-statusline.json"
