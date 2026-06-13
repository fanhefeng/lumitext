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

# A prior `xcodebuild test` embeds LumitextAppTests.xctest into the app's
# PlugIns (TEST_HOST layout) AND injects ~37MB of XCTest/Testing frameworks
# into Contents/Frameworks. Incremental builds over build/Debug inherit both —
# strip them BEFORE signing (removing after would break the seal), so tests
# never ship in an installed or shared copy. A clean app build has no
# Frameworks dir, so removing the known test frameworks (then the dir if empty)
# is safe; a future real dependency (e.g. Sparkle) is named explicitly elsewhere.
rm -rf "$APP"/Contents/PlugIns/*.xctest
rm -rf "$APP"/Contents/Frameworks/{XCTest,XCTestCore,XCTestSupport,XCTAutomationSupport,XCUIAutomation,XCUnit,Testing}.framework \
       "$APP"/Contents/Frameworks/libXCTest*.dylib
rmdir "$APP"/Contents/Frameworks 2>/dev/null || true

echo "== sign (inside-out, ad-hoc + entitlements) =="
# Dev uses the .debug entitlements (adds disable-library-validation) because
# ad-hoc signing has no Team ID for library validation. Release (scripts/sign.sh)
# uses the hardened Saver/LumitextSaver.entitlements instead.
codesign --force --sign - \
    --entitlements Saver/LumitextSaver.debug.entitlements \
    "$APPEX"
codesign --force --sign - \
    --entitlements App/Lumitext.entitlements \
    "$APP"

echo "== verify entitlements stuck =="
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q "/Users/Shared/Lumitext" \
    && echo "appex: /Users/Shared/Lumitext read exception ✓" \
    || { echo "appex: shared-dir read exception MISSING"; exit 1; }
codesign --verify --deep --strict "$APP" && echo "signature valid ✓"

echo "== install to /Applications (pluginkit prefers it; never run from DerivedData) =="
# Quit a running instance first — replacing a live bundle leaves the old code
# running and confuses LaunchServices (see CLAUDE.md "Install & register").
osascript -e 'tell application "Lumitext" to quit' 2>/dev/null || true
# `quit` is asynchronous — wait (bounded) for the process to actually exit.
# ABORT if it's still alive: swapping the bundle under a live process leaves
# stale code running and confuses LaunchServices (see CLAUDE.md).
for _ in $(seq 1 50); do pgrep -xq Lumitext || break; sleep 0.2; done
if pgrep -xq Lumitext; then
    echo "ERROR: Lumitext is still running after 10s; quit it and re-run." >&2
    exit 1
fi

# Stage-then-swap with a restore path: the old install is moved ASIDE (not
# deleted) until the new copy fully landed and verified — neither a failed cp
# (cp -R keeps going past errors, leaving a partial bundle) nor a failed mv
# may leave /Applications with no working build.
STAGED="/Applications/.Lumitext-staged-$$.app"
OLD="/Applications/.Lumitext-old-$$.app"
# Leftovers from a previous run killed before its trap fired (kill -9, crash).
# PID-aware: a CONCURRENT run's in-flight staging/backup must never be raided —
# deleting another run's move-aside backup defeats its restore path.
for leftover in /Applications/.Lumitext-staged-*.app /Applications/.Lumitext-old-*.app; do
    [ -e "$leftover" ] || continue
    pid="${leftover##*-}"; pid="${pid%.app}"
    # `ps -p` reports existence regardless of owner. `kill -0` would fail with
    # EPERM for a LIVE process owned by ANOTHER admin user (/Applications is
    # admin-shared), wrongly raiding that run's in-flight backup and defeating its
    # restore path — only delete when the process is genuinely gone. Mirrors the
    # ESRCH-only Swift cleanup in ActivationManager (commit eb5132a).
    if ! ps -p "$pid" >/dev/null 2>&1; then rm -rf "$leftover"; fi
done
trap 'rm -rf "$STAGED" "$OLD"' EXIT
cp -R "$APP" "$STAGED"
codesign --verify --deep --strict "$STAGED"
if [ -d /Applications/Lumitext.app ]; then
    mv /Applications/Lumitext.app "$OLD"
fi
if ! mv "$STAGED" /Applications/Lumitext.app; then
    if [ -d "$OLD" ]; then
        if mv "$OLD" /Applications/Lumitext.app; then
            echo "install failed; previous app restored" >&2
        else
            # Restore ALSO failed: $OLD is now the ONLY surviving copy of the
            # previous install. Drop it from the cleanup trap so we never delete
            # the user's last working build; leave it for manual recovery.
            trap 'rm -rf "$STAGED"' EXIT
            echo "install failed AND restore failed; previous app preserved — restore it with:" >&2
            echo "  mv '$OLD' /Applications/Lumitext.app" >&2
        fi
    fi
    exit 1
fi
rm -rf "$OLD"

echo "== register =="
# pkd elects ONE path per bundle ID and a build-dir registration shadows the
# /Applications install (the stale-election wedge — see make-share-zip.sh).
# Deregister the freshly built copy before registering the installed one.
pluginkit -r "$PWD/$APPEX" 2>/dev/null || true
pluginkit -a /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex || true
sleep 1
if pluginkit -m -v -p com.apple.screensaver 2>/dev/null | grep -i lumitext; then
    echo "registered ✓"
else
    echo "WARNING: not yet visible in pluginkit (registration can lag); retry later with:"
    echo "  pluginkit -m -v -p com.apple.screensaver | grep -i lumitext"
fi
