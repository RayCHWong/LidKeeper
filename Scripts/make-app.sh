#!/bin/bash
#
# Builds LidKeeper as a double-clickable .app bundle (menu-bar-only).
#
# Usage:   bash Scripts/make-app.sh
# Output:  build/LidKeeper.app  (drag it to /Applications)
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="LidKeeper"
BUNDLE_ID="app.lidkeeper.LidKeeper"
VERSION="1.0"
OUT="build/${APP_NAME}.app"

echo "▸ Building release binary…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "▸ Assembling ${OUT}…"
rm -rf "${OUT}"
mkdir -p "${OUT}/Contents/MacOS" "${OUT}/Contents/Resources"
cp "${BIN}" "${OUT}/Contents/MacOS/${APP_NAME}"

cat > "${OUT}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Agent app: lives in the menu bar, no Dock icon, no window. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code signing…"
codesign --force --sign - "${OUT}" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app still runs locally)"

echo "✅ Done: ${OUT}"
echo "   Launch it:  open \"${OUT}\""
echo "   Install it: cp -R \"${OUT}\" /Applications/"
