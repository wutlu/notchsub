#!/usr/bin/env bash
# design/make-icon.swift → Resources/AppIcon.icns ve landing page ikonları
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swift design/make-icon.swift "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
mkdir -p docs/assets
cp "$TMP/icon.png" design/icon-1024.png
sips -z 512 512 "$TMP/icon.png" --out docs/assets/icon.png >/dev/null
sips -z 64 64 "$TMP/icon.png" --out docs/assets/favicon.png >/dev/null
echo "✓ Resources/AppIcon.icns"
