#!/usr/bin/env bash
# NotchSub tek satır kurulum:
#   curl -fsSL https://wutlu.github.io/notchsub/install.sh | bash
set -euo pipefail

REPO="wutlu/notchsub"
URL="https://github.com/$REPO/releases/latest/download/NotchSub.zip"
APP="/Applications/NotchSub.app"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "NotchSub only runs on macOS."; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "NotchSub requires a Mac with Apple Silicon (M1 or later)."; exit 1; }
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 15 )) || { echo "NotchSub requires macOS 15 Sequoia or later."; exit 1; }

bold "↓ Downloading NotchSub…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar "$URL" -o "$TMP/NotchSub.zip"
ditto -x -k "$TMP/NotchSub.zip" "$TMP"

bold "→ Installing to /Applications…"
pkill -x NotchSub 2>/dev/null || true
if [[ -w /Applications ]]; then
  rm -rf "$APP" && mv "$TMP/NotchSub.app" "$APP"
else
  sudo rm -rf "$APP" && sudo mv "$TMP/NotchSub.app" "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

bold "✓ Installed. Opening NotchSub — click the notch to start."
open "$APP"
