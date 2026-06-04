#!/bin/bash
#
# make-share-zip.sh — package an (ad-hoc-signed) Lumitext.app into a friend-shareable
# zip, with the Chinese install instructions alongside the app.
#
#   ./scripts/make-share-zip.sh <path-to-Lumitext.app> [output.zip]
#
# Why a zip and not a DMG: pre-notarization, apps dragged from a quarantined DMG still
# inherit quarantine, so a DMG buys nothing (ADR-0002). `ditto -c -k` preserves the
# extended attributes/resource structure the code signature seals — a signature broken
# in transit removes Tahoe's "Open Anyway" option entirely, so we verify the zip
# round-trips with the signature intact before printing the result.
#
# Recipient experience (macOS 26+ only):
#   - USB stick / scp: no quarantine is ever set → opens with zero prompts.
#   - AirDrop / IM / web download: quarantined → System Settings "Open Anyway",
#     or `xattr -dr com.apple.quarantine` — both spelled out in 安装说明.txt.
#
set -euo pipefail

APP="${1:?usage: make-share-zip.sh <Lumitext.app> [output.zip]}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
OUT="${2:-$(dirname "$APP")/Lumitext-$VERSION-preview.zip}"
STAGE="$(mktemp -d)/Lumitext-$VERSION"

codesign --verify --deep --strict "$APP"   # refuse to package a broken signature

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$REPO/distribution/安装说明.txt" "$STAGE/"

rm -f "$OUT"
ditto -c -k --keepParent "$STAGE" "$OUT"

# Round-trip check: the signature must survive compression, or recipients hit a
# no-"Open Anyway" dead end instead of the documented unblock flow.
UNPACK="$(mktemp -d)"
ditto -x -k "$OUT" "$UNPACK"
codesign --verify --deep --strict "$UNPACK/Lumitext-$VERSION/Lumitext.app"
rm -rf "$(dirname "$STAGE")" "$UNPACK"

echo "$OUT"
shasum -a 256 "$OUT"
