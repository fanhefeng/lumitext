#!/bin/bash
#
# make-dmg.sh — package Lumitext.app into a distributable DMG with an /Applications
# drag-target. A DMG is the right artifact for NOTARIZED releases (mounts and installs
# with zero Gatekeeper prompts once stapled). Note: apps dragged from a quarantined DMG
# still inherit quarantine, so pre-notarization a DMG has no advantage over a zip —
# share ad-hoc preview builds via scripts/make-share-zip.sh instead (ADR-0002).
#
#   ./scripts/make-dmg.sh <path-to-Lumitext.app> [output.dmg]
#
set -euo pipefail

APP="${1:?usage: make-dmg.sh <Lumitext.app> [output.dmg]}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
OUT="${2:-$(dirname "$APP")/Lumitext-$VERSION.dmg}"
# trap (not a tail rm) so the staging dir is cleaned even when a step fails
# under set -e.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/Lumitext"

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "Lumitext $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$OUT" >/dev/null

echo "$OUT"
shasum -a 256 "$OUT"
