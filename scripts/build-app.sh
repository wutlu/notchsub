#!/usr/bin/env bash
# NotchSub.app paketini derler: ./scripts/build-app.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

APP="build/NotchSub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchSub" "$APP/Contents/MacOS/NotchSub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# SwiftPM kaynak paketleri (bağımlılıkların ihtiyaç duyduğu dosyalar)
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --sign - "$APP"
echo "✓ $APP hazır"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x NotchSub 2>/dev/null || true
  open "$APP"
fi
