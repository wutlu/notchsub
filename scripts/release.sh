#!/usr/bin/env bash
# Sürüm paketleri üretir: ./scripts/release.sh 0.2.0 [--publish]
#   dist/NotchSub-<sürüm>.dmg   → sürükle-bırak kurulum
#   dist/NotchSub.zip           → install.sh'nin indirdiği paket
# --publish: GitHub Release oluşturur ve dosyaları yükler (gh CLI gerekir).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Kullanım: release.sh <sürüm> [--publish]}"
PLIST=Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$PLIST"

./scripts/build-app.sh

rm -rf dist && mkdir -p dist/dmg
ditto -c -k --keepParent build/NotchSub.app dist/NotchSub.zip

cp -R build/NotchSub.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "NotchSub" -srcfolder dist/dmg -fs HFS+ -format UDZO -ov "dist/NotchSub-$VERSION.dmg" >/dev/null
cp "dist/NotchSub-$VERSION.dmg" dist/NotchSub.dmg
rm -rf dist/dmg
(cd dist && shasum -a 256 NotchSub.zip NotchSub.dmg > SHA256SUMS.txt)
echo "✓ dist/ hazır:"; ls -lh dist

if [[ "${2:-}" == "--publish" ]]; then
  gh release create "v$VERSION" dist/NotchSub.dmg dist/NotchSub.zip dist/SHA256SUMS.txt \
    --title "NotchSub $VERSION" --generate-notes
fi
