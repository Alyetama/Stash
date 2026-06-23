#!/bin/bash
# Build Stash.app and package it into a styled drag-to-install .dmg under dist/.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stash"
VOL="Stash"
BG="dmg/background.png"
RW="/tmp/stash_rw.dmg"
STAGE="$(mktemp -d)/stage"
mkdir -p "$STAGE"
cleanup() { rm -rf "$(dirname "$STAGE")" "$RW" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Building the app into a staging folder…"
INSTALL_DIR="$STAGE" ./build.sh release

echo "==> Adding background, Applications shortcut, volume icon…"
mkdir "$STAGE/.background"
cp "$BG" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"
cp "Sources/Stash/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

echo "==> Creating writable disk image…"
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 30 ))
rm -f "$RW"
hdiutil create -size "${SIZE}m" -fs HFS+ -volname "$VOL" "$RW" >/dev/null

DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOL"
sleep 1
cp -R "$STAGE/." "$MOUNT/"
SetFile -a C "$MOUNT" || true                 # volume has a custom icon
SetFile -a E "$MOUNT/$APP_NAME.app" || true   # hide the .app extension on the label

echo "==> Laying out the Finder window…"
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {220, 140, 880, 580}
    set theVO to the icon view options of container window
    set arrangement of theVO to not arranged
    set icon size of theVO to 128
    set text size of theVO to 12
    set background picture of theVO to file ".background:background.png"
    set position of item "Stash.app" of container window to {175, 200}
    set position of item "Applications" of container window to {485, 200}
    update without registering applications
    delay 1.5
    close
  end tell
end tell
OSA

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true

echo "==> Compressing…"
mkdir -p dist
rm -f "dist/$APP_NAME.dmg"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "dist/$APP_NAME.dmg" >/dev/null

echo ""
echo "✅ Styled disk image: dist/$APP_NAME.dmg"
