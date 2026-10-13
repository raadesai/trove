#!/bin/bash
# Save the frontmost Chrome tab to Trove. Triggered by Karabiner (double-tap fn).
# Config (endpoint + token) is read from an untracked local file, never committed:
#   ~/.config/trove/config  (copy mac-fn-hotkey/config.example and fill it in)
CONFIG="$HOME/.config/trove/config"
[ -f "$CONFIG" ] && source "$CONFIG"
ENDPOINT="${TROVE_ENDPOINT:-}"
# Token: prefer the config file, fall back to the legacy ~/.config/trove/save_token
TOKEN="${TROVE_SAVE_TOKEN:-$(cat "$HOME/.config/trove/save_token" 2>/dev/null)}"
if [ -z "$ENDPOINT" ] || [ -z "$TOKEN" ]; then
  osascript -e 'display notification "Trove not configured — see ~/.config/trove/config" with title "Trove"'
  exit 1
fi

URL=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window' 2>/dev/null)
TITLE=$(osascript -e 'tell application "Google Chrome" to get title of active tab of front window' 2>/dev/null)

if [ -z "$URL" ]; then
  osascript -e 'display notification "No Chrome tab found" with title "Trove"'
  exit 1
fi

# ✈ Fire the paper-plane animation *immediately* — optimistically, before the
# network save below — so it feels instant off the double-tap. We already have a
# valid URL, and saves practically never fail; the animation must not wait on the
# round-trip. (Hammerspoon CLI — the URL-scheme route drops events on this setup.)
# Backgrounded so it can never block.
(/opt/homebrew/bin/hs -c "trovePlane()" >/dev/null 2>&1 &)

BODY=$(python3 - "$URL" "$TITLE" <<'EOF'
import json, sys
print(json.dumps({"url": sys.argv[1], "title": sys.argv[2] or None}))
EOF
)

if ! curl -sf -X POST "$ENDPOINT" \
  -H "content-type: application/json" \
  -H "x-token: $TOKEN" \
  -d "$BODY" > /dev/null; then
  # Rare: the optimistic plane already flew, so flag the failure explicitly.
  osascript -e 'display notification "Save failed" with title "Trove"'
fi
