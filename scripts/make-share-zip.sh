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

# Defensive: if the source copy's appex ever got registered with pluginkit (e.g. the
# app was launched from build/Release), that registration shadows the /Applications
# install — pkd elects one path per bundle ID, and `pluginkit -a` from anywhere else
# then silently no-ops (see CLAUDE.md "Install & register"). Deregister the source
# path so packaging never leaves a stale election behind. Never touch the
# /Applications copy itself — that's the registration we want to keep.
APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
case "$APP_ABS" in
  /Applications/*) ;;
  *) pluginkit -r "$APP_ABS/Contents/PlugIns/LumitextSaver.appex" 2>/dev/null || true ;;
esac

echo "$OUT"
shasum -a 256 "$OUT"
