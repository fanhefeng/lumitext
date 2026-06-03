#!/bin/bash
#
# dev-build-install.sh — the dev loop in one shot:
#   regenerate project → build → ad-hoc sign WITH entitlements (inside-out)
#   → install to /Applications → register with pluginkit.
#
# Why post-build signing: declaring CODE_SIGN_ENTITLEMENTS with an App Groups
# entitlement makes Xcode's build system demand a provisioning profile, which
# ad-hoc dev signing can't provide. `codesign` itself has no such check.
# Release builds (M5) replace this with Developer ID via scripts/sign.sh.
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Debug/Lumitext.app"
APPEX="$APP/Contents/PlugIns/LumitextSaver.appex"

echo "== xcodegen =="
xcodegen generate --quiet

echo "== build =="
xcodebuild -project Lumitext.xcodeproj -scheme Lumitext -configuration Debug \
    build SYMROOT="$PWD/build" -quiet

echo "== sign (inside-out, ad-hoc + entitlements) =="
codesign --force --sign - \
    --entitlements Saver/LumitextSaver.entitlements \
    "$APPEX"
codesign --force --sign - \
    --entitlements App/Lumitext.entitlements \
    "$APP"

echo "== verify entitlements stuck =="
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q "application-groups" \
    && echo "appex: application-groups ✓" \
    || { echo "appex: application-groups MISSING"; exit 1; }
codesign --verify --deep --strict "$APP" && echo "signature valid ✓"

echo "== install to /Applications (pluginkit prefers it; never run from DerivedData) =="
rm -rf /Applications/Lumitext.app
cp -R "$APP" /Applications/

echo "== register =="
pluginkit -a /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex || true
sleep 1
if pluginkit -m -v -p com.apple.screensaver 2>/dev/null | grep -i lumitext; then
    echo "registered ✓"
else
    echo "WARNING: not yet visible in pluginkit (registration can lag); retry later with:"
    echo "  pluginkit -m -v -p com.apple.screensaver | grep -i lumitext"
fi
