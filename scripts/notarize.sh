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
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

submit() { # <path-to-zip-or-dmg>
    # `notarytool --wait` exits 0 even when the result is Invalid/Rejected — same
    # trap as `pluginkit -a` (see CLAUDE.md): the exit code is not the result.
    # The only truth is the final `status:` line, so stream it live (tee) AND
    # capture it to assert Accepted; on any other outcome dump the notary log so
    # we never staple a rejected artifact and report it as success.
    local out
    out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1 | tee /dev/stderr)"
    if ! grep -qE 'status:[[:space:]]+Accepted' <<<"$out"; then
        echo "ERROR: notarization did NOT succeed for $1 (see status above)" >&2
        local id
        id="$(grep -oE 'id: [0-9a-f-]{36}' <<<"$out" | head -1 | awk '{print $2}')"
        [ -n "${id:-}" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        return 1
    fi
}

echo "== 1. notarize the app (via a zip for submission) =="
APPZIP="$WORK/Lumitext.zip"
ditto -c -k --keepParent "$APP" "$APPZIP"
submit "$APPZIP"

echo "== 2. staple the app =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 3. build DMG around the stapled app =="
# NOT `make-dmg.sh | head -1`: make-dmg prints two lines (path + shasum), and
# head exiting after the first would SIGPIPE the producer — exit 141 under
# pipefail, killing the pipeline right after building an un-notarized DMG.
DMG_OUT="$("$REPO/scripts/make-dmg.sh" "$APP")"
DMG="${DMG_OUT%%$'\n'*}"

echo "== 4. notarize + staple the DMG (double-staple) =="
submit "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "== 5. final Gatekeeper check =="
# Disk images are assessed under the `open` policy with the primary-signature
# context (Apple's documented notarization check) — `-t install` is for
# installer .pkgs and rejects everything else.
spctl -a -vvv -t open --context context:primary-signature "$DMG" || true
echo "release artifact: $DMG"
shasum -a 256 "$DMG"
