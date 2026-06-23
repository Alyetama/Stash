#!/bin/bash
# Build Stash.app and package it into a drag-to-install .dmg under dist/.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Stash"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Building the app into a staging folder…"
INSTALL_DIR="$STAGE" ./build.sh release

echo "==> Adding /Applications shortcut…"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "dist/$APP_NAME.dmg"

echo "==> Creating disk image…"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "dist/$APP_NAME.dmg" >/dev/null

echo ""
echo "✅ Disk image: dist/$APP_NAME.dmg"
echo "   Open it and drag \"$APP_NAME\" onto Applications."
