#!/bin/bash
#
# notarize.sh — notarize a signed app, build a DMG, notarize & double-staple it.
#
#   ./scripts/notarize.sh <path-to-signed-Lumitext.app>
#
# Requires a notarytool credential. Either store one once:
#   xcrun notarytool store-credentials lumitext-notary \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# then set:  export LUMITEXT_NOTARY_PROFILE=lumitext-notary
# (or use an App Store Connect API key with --key/--key-id/--issuer.)
#
set -euo pipefail

APP="${1:?usage: notarize.sh <signed-Lumitext.app>}"
PROFILE="${LUMITEXT_NOTARY_PROFILE:?set LUMITEXT_NOTARY_PROFILE to a stored notarytool profile}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

submit() { # <path-to-zip-or-dmg>
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

echo "== 1. notarize the app (via a zip for submission) =="
APPZIP="$(mktemp -d)/Lumitext.zip"
ditto -c -k --keepParent "$APP" "$APPZIP"
submit "$APPZIP"

echo "== 2. staple the app =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 3. build DMG around the stapled app =="
DMG="$("$REPO/scripts/make-dmg.sh" "$APP" | head -1)"

echo "== 4. notarize + staple the DMG (double-staple) =="
submit "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "== 5. final Gatekeeper check =="
spctl -a -vvv -t install "$DMG" || true
echo "release artifact: $DMG"
shasum -a 256 "$DMG"
