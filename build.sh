#!/bin/bash
# Build CopyEm Search.app from the Swift package and install it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"          # pass "debug" for a faster, unoptimized build
APP_NAME="CopyEm Search"
BUNDLE_ID="com.local.copyemsearch"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"   # override with INSTALL_DIR=... if desired
APP_DIR="$INSTALL_DIR/$APP_NAME.app"

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/CopyEmSearch"

echo "==> Assembling app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/CopyEmSearch"
cp "Sources/CopyEmSearch/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Ad-hoc code signing…"
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ Built: $APP_DIR"
echo "   Launch with:  open \"$APP_DIR\""
echo "   The menu-bar icon (magnifying glass) appears at the top-right."
echo "   Global hotkey to search:  ⌃⌥⌘C"
