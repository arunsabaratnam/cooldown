#!/bin/bash
# Checks, on this machine, whether each quota source the app relies on actually
# answers — before you build anything. Prints what it finds and nothing else;
# it changes no files and sends no prompts.
set -uo pipefail

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
dim()   { printf '\033[2m%s\033[0m\n' "$1"; }

echo "=== Claude ==="
if command -v claude >/dev/null 2>&1; then
  green "claude found at $(command -v claude)"
else
  red "claude is not on PATH"
fi

TOKEN=""
if TOKEN_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null); then
  green "OAuth token found in the login Keychain"
elif [ -f "$HOME/.claude/.credentials.json" ]; then
  TOKEN_JSON=$(cat "$HOME/.claude/.credentials.json")
  green "OAuth token found in ~/.claude/.credentials.json"
else
  red "no OAuth token found (Keychain or ~/.claude/.credentials.json)"
  TOKEN_JSON=""
fi

if [ -n "$TOKEN_JSON" ]; then
  TOKEN=$(printf '%s' "$TOKEN_JSON" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
o = d.get("claudeAiOauth") or d.get("oauth") or d
print(o.get("accessToken") or o.get("access_token") or "")' 2>/dev/null)
fi

if [ -n "$TOKEN" ]; then
  echo "--- GET https://api.anthropic.com/api/oauth/usage"
  CODE=$(curl -sS -m 20 -o /tmp/cooldown-probe-claude.json -w '%{http_code}' \
    https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)
  if [ "$CODE" = "200" ]; then
    green "HTTP 200"
    python3 -m json.tool /tmp/cooldown-probe-claude.json 2>/dev/null | head -40
  else
    red "HTTP $CODE"
    head -c 400 /tmp/cooldown-probe-claude.json 2>/dev/null; echo
    dim "This endpoint is undocumented, so a non-200 here means the app falls back to the status line snapshot."
  fi
else
  dim "Skipping the usage endpoint: no token to send."
fi

if [ -f "$HOME/.cooldown/claude-statusline.json" ]; then
  green "status line snapshot present ($(date -r "$HOME/.cooldown/claude-statusline.json" '+%Y-%m-%d %H:%M'))"
  python3 -c 'import json;d=json.load(open("'"$HOME"'/.cooldown/claude-statusline.json"));print(json.dumps(d.get("rate_limits",{}),indent=2))' 2>/dev/null
else
  dim "no status line snapshot yet (run scripts/install-claude-statusline.sh to add the fallback source)"
fi

echo
echo "=== Codex ==="
if command -v codex >/dev/null 2>&1; then
  green "codex found at $(command -v codex)"
  echo "--- codex app-server account/rateLimits/read"
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"cooldown-probe","version":"0.1"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"initialized","params":{}}'
    sleep 1
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}'
    sleep 3
  } | codex app-server 2>/dev/null | grep -F '"id":2' | head -1 | python3 -m json.tool 2>/dev/null \
    || red "no reply to account/rateLimits/read (older codex, or not signed in)"
else
  red "codex is not on PATH"
fi

LATEST=$(find "$HOME/.codex/sessions" -name '*.jsonl' -mtime -7 2>/dev/null | head -50)
if [ -n "$LATEST" ]; then
  FOUND=$(printf '%s\n' "$LATEST" | xargs grep -h -F '"token_count"' 2>/dev/null | grep -F 'rate_limits' | tail -1)
  if [ -n "$FOUND" ]; then
    green "session log fallback has rate limits"
    printf '%s' "$FOUND" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps(d["payload"].get("rate_limits"),indent=2))' 2>/dev/null
  else
    dim "session logs found, but none carry rate_limits yet"
  fi
else
  dim "no Codex session logs in the last 7 days"
fi
