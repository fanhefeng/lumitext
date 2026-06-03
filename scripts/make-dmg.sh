#!/bin/bash
#
# make-dmg.sh — package Lumitext.app into a distributable DMG with an /Applications
# drag-target. A DMG (vs a zip) is preferred: dragging from a mounted DMG avoids the
# quarantine xattr that triggers Tahoe's buried "Open Anyway" flow.
#
#   ./scripts/make-dmg.sh <path-to-Lumitext.app> [output.dmg]
#
set -euo pipefail

APP="${1:?usage: make-dmg.sh <Lumitext.app> [output.dmg]}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
OUT="${2:-$(dirname "$APP")/Lumitext-$VERSION.dmg}"
STAGE="$(mktemp -d)/Lumitext"

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Lumitext $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$OUT" >/dev/null

rm -rf "$(dirname "$STAGE")"
echo "$OUT"
shasum -a 256 "$OUT"
