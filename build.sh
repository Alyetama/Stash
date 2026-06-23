#!/bin/bash
# Build Stash.app from the Swift package and install it to /Applications.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"          # pass "debug" for a faster, unoptimized build
APP_NAME="Stash"
BUNDLE_ID="com.local.stash"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"   # override with INSTALL_DIR=... if desired
APP_DIR="$INSTALL_DIR/$APP_NAME.app"

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Stash"

echo "==> Assembling app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/Stash"
cp "Sources/Stash/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Sources/Stash/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Prefer the stable self-signed identity (run ./setup-signing.sh once) so the
# signature doesn't change every build — keeps the Keychain from re-prompting.
SIGN_ID="Stash Code Signing"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    echo "==> Code signing with '$SIGN_ID'…"
    codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
    echo "==> Ad-hoc code signing (run ./setup-signing.sh for a stable signature)…"
    codesign --force --deep --sign - "$APP_DIR"
fi

echo ""
echo "✅ Built: $APP_DIR"
echo "   Launch with:  open \"$APP_DIR\""
echo "   A menu-bar icon appears at the top-right."
echo "   Global hotkey to search:  ⌃⌥⌘C"
