#!/bin/bash
#
# sign.sh — inside-out code signing for release.
#
#   ./scripts/sign.sh <path-to-Lumitext.app> [signing-identity]
#
# Signs nested code first (frameworks/dylibs, then the embedded .appex), then the
# outer app — the order codesign requires. Uses the hardened runtime + a secure
# timestamp when a real Developer ID is given (both are required for notarization).
#
# Signing identity resolution:
#   1. the 2nd argument, or
#   2. $LUMITEXT_SIGN_IDENTITY, or
#   3. "-" (ad-hoc) for local mechanics testing — NOT notarizable.
#
# Find your identity with:  security find-identity -v -p codesigning
# (look for "Developer ID Application: Your Name (TEAMID)")
#
set -euo pipefail

APP="${1:?usage: sign.sh <Lumitext.app> [identity]}"
IDENTITY="${2:-${LUMITEXT_SIGN_IDENTITY:--}}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENT="$REPO/App/Lumitext.entitlements"
SAVER_ENT="$REPO/Saver/LumitextSaver.entitlements"

if [ "$IDENTITY" = "-" ]; then
    echo "WARNING: signing ad-hoc (-). Result is NOT notarizable; for local testing only."
    RUNTIME_FLAGS=()
else
    echo "Signing with: $IDENTITY"
    RUNTIME_FLAGS=(--options runtime --timestamp)
fi

sign() { # <entitlements-or-""> <path>
    local ent="$1" path="$2"
    if [ -n "$ent" ]; then
        codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} --entitlements "$ent" "$path"
    else
        codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} "$path"
    fi
}

echo "== 1. nested frameworks & dylibs (deepest first) =="
# Sign any embedded frameworks (e.g. Sparkle) and their nested helpers, then loose dylibs.
if [ -d "$APP/Contents/Frameworks" ]; then
    # XPCServices / helper apps inside frameworks (e.g. Sparkle's Autoupdate, Updater.app)
    find "$APP/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" \) -print0 |
        while IFS= read -r -d '' item; do sign "" "$item"; done
    find "$APP/Contents/Frameworks" -type d -name "*.framework" -print0 |
        while IFS= read -r -d '' fw; do sign "" "$fw"; done
    find "$APP/Contents/Frameworks" -type f -name "*.dylib" -print0 |
        while IFS= read -r -d '' dy; do sign "" "$dy"; done
fi

echo "== 2. embedded screensaver extension =="
sign "$SAVER_ENT" "$APP/Contents/PlugIns/LumitextSaver.appex"

echo "== 3. outer app =="
sign "$APP_ENT" "$APP"

echo "== verify =="
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$IDENTITY" != "-" ]; then
    echo "== Gatekeeper assessment =="
    spctl -a -vvv -t install "$APP" || echo "(spctl will pass only after notarization+staple)"
fi
echo "signed: $APP"
