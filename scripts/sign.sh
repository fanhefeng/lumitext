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
# Ad-hoc (-) has no Team ID, so the saver appex needs disable-library-validation
# or pkd/ScreenSaverEngine refuses to load it — that key lives ONLY in the .debug
# entitlements (the same reason dev-build-install.sh uses them). A real Developer
# ID uses the hardened entitlements, which notarization requires WITHOUT that
# exception. Picking the wrong one ships a release whose screensaver never loads.
if [ "$IDENTITY" = "-" ]; then
    SAVER_ENT="$REPO/Saver/LumitextSaver.debug.entitlements"
else
    SAVER_ENT="$REPO/Saver/LumitextSaver.entitlements"
fi

# A prior `xcodebuild test` embeds the hosted test bundle into PlugIns — strip
# it BEFORE signing (it must never ship, and notarization would choke on it).
rm -rf "$APP"/Contents/PlugIns/*.xctest
# Same root cause: `xcodebuild test` also injects ~37MB of XCTest/Testing
# frameworks into Contents/Frameworks. The signing loop below would otherwise
# sign them straight into the notarized DMG — baking test code into the release.
# dev-build-install.sh and make-share-zip.sh already strip/refuse these; the
# release path must too. (rmdir clears the dir only if it's now empty; a real
# future dependency like Sparkle leaves it populated and rmdir no-ops.)
rm -rf "$APP"/Contents/Frameworks/{XCTest,XCTestCore,XCTestSupport,XCTAutomationSupport,XCUIAutomation,XCUnit,Testing}.framework \
       "$APP"/Contents/Frameworks/libXCTest*.dylib
rmdir "$APP"/Contents/Frameworks 2>/dev/null || true

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
# Sign nested code strictly inside-out: helpers and dylibs INSIDE a framework
# must be signed BEFORE the enclosing .framework, or re-signing them afterwards
# breaks the framework's seal.
if [ -d "$APP/Contents/Frameworks" ]; then
    # 1a. XPCServices / helper apps inside frameworks (e.g. Sparkle's Updater.app)
    find "$APP/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" \) -print0 |
        while IFS= read -r -d '' item; do sign "" "$item"; done
    # 1a'. BARE executable helpers (Sparkle ships Autoupdate as a plain Mach-O,
    # not an .app/.xpc — the patterns above miss it and notarization would fail)
    find "$APP/Contents/Frameworks" -type f -name "Autoupdate" -print0 |
        while IFS= read -r -d '' helper; do sign "" "$helper"; done
    # 1b. ALL dylibs (framework-internal and loose) — before the framework shells
    find "$APP/Contents/Frameworks" -type f -name "*.dylib" -print0 |
        while IFS= read -r -d '' dy; do sign "" "$dy"; done
    # 1c. the framework bundles themselves, last
    find "$APP/Contents/Frameworks" -type d -name "*.framework" -print0 |
        while IFS= read -r -d '' fw; do sign "" "$fw"; done
fi

echo "== 2. embedded screensaver extension =="
sign "$SAVER_ENT" "$APP/Contents/PlugIns/LumitextSaver.appex"

echo "== 3. outer app =="
sign "$APP_ENT" "$APP"

echo "== verify =="
# The MOST critical sentinel: an appex signed WITHOUT com.apple.security.app-sandbox
# is SILENTLY filtered out of pkd discovery — `pluginkit -a` exits 0 but registers
# nothing (verified 2026-06-04; see CLAUDE.md). This matters more than the read
# exception below: lose the sandbox key and registration fails with NO error, so
# check it first and hard-fail. Guards against a hardened-entitlements file edited
# in a way that keeps the path string but drops the sandbox key.
APPEX="$APP/Contents/PlugIns/LumitextSaver.appex"
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q "app-sandbox" \
    || { echo "appex: com.apple.security.app-sandbox MISSING — pkd will silently filter it"; exit 1; }
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q "/Users/Shared/Lumitext" \
    || { echo "appex: /Users/Shared/Lumitext read exception MISSING"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$IDENTITY" != "-" ]; then
    echo "== Gatekeeper assessment =="
    # `--type exec` (the default policy) is the correct assessment for an .app;
    # `-t install` is the installer-package policy and ALWAYS rejects app
    # bundles, even correctly notarized ones.
    spctl -a -vvv --type exec "$APP" \
        || echo "(rejected: expected before notarization+staple; rerun after notarize.sh)"
fi
echo "signed: $APP"
