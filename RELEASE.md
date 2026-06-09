# Release runbook

Lumitext ships as a **Developer-ID-signed, notarized DMG** (primary) plus a **Homebrew
cask** (secondary). It is NOT distributed via the Mac App Store — `.appex` screensavers
using the private ScreenSaver API and the `/Users/Shared` temporary-exception config
channel are not MAS-eligible.

Everything below is automated by `scripts/`; the only prerequisites are owner-only
accounts (see PLAN.md M0). All scripts live in `scripts/` and are idempotent.

## One-time setup (owner)

1. **Apple Developer Program** ($99/yr) → note your **Team ID**.
2. **Developer ID Application certificate**: Xcode → Settings → Accounts → Manage
   Certificates → + → "Developer ID Application". Confirm with:
   ```bash
   security find-identity -v -p codesigning      # look for "Developer ID Application: … (TEAMID)"
   ```
3. **notarytool credential** (store once):
   ```bash
   xcrun notarytool store-credentials lumitext-notary \
     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
   export LUMITEXT_NOTARY_PROFILE=lumitext-notary
   ```
4. **Sparkle EdDSA keys** (for auto-update; see "Enabling Sparkle" below).

> No App Group registration is needed: the config channel is
> `/Users/Shared/Lumitext/config.json` via a scoped temporary-exception entitlement
> (see ADR-0001 addendum — Tahoe's TCC rejects group containers for this setup, and
> no entitlements file references one). With a real Team ID a Team-ID-prefixed App
> Group *could* become an option later; treat that as future work, not setup.

## Cutting a release

```bash
# 1. bump version
#    edit MARKETING_VERSION (and CURRENT_PROJECT_VERSION) in project.yml, AND the
#    hardcoded version in distribution/安装说明.txt (first line), then:
xcodegen generate

# 2. build Release
xcodebuild -project Lumitext.xcodeproj -scheme Lumitext -configuration Release \
  build SYMROOT=$PWD/build

# 3. sign with your Developer ID (inside-out, hardened runtime, timestamped)
LUMITEXT_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/sign.sh build/Release/Lumitext.app

# 4. notarize app + DMG, double-staple  (needs LUMITEXT_NOTARY_PROFILE)
./scripts/notarize.sh build/Release/Lumitext.app
#    → prints the final Lumitext-<version>.dmg and its SHA-256

# 5. publish: create a GitHub release tagged v<version>, upload the DMG
gh release create "v<version>" build/Release/Lumitext-<version>.dmg \
  --title "Lumitext <version>" --notes "…"

# 6. update the Homebrew cask: set version + sha256 + (url auto-derives) in
#    distribution/lumitext.rb, run `brew style --cask` + `brew audit --cask`,
#    push to your tap (or open a homebrew-cask PR once notable).

# 7. ONLY once Sparkle is actually compiled in (see "Enabling Sparkle" below —
#    deferred; skip this step until then): update distribution/appcast.xml and
#    publish it where SUFeedURL points. In the SAME release, add
#    `auto_updates true` back to the cask.
```

## Verifying the release on a clean machine / second account

```bash
# --type exec is the policy for app bundles (-t install is for installer .pkgs
# and ALWAYS rejects an .app, even a correctly notarized one)
spctl -a -vvv --type exec Lumitext.app     # → "accepted, source=Notarized Developer ID"
stapler validate Lumitext.app && stapler validate Lumitext-<version>.dmg
# Then: download the DMG, drag to /Applications, launch → no Gatekeeper prompt.
# Open System Settings → Screen Saver → LumitextSaver should appear (re-register if not).
```

## Enabling Sparkle auto-update (deferred until first signed release)

Sparkle is intentionally NOT yet compiled into the app: it needs a Developer ID (so the
embedded framework can be signed) and a published appcast + EdDSA key to be useful, all
of which only exist at release time. To enable:

1. Add the dependency in `project.yml` under `packages:`
   ```yaml
   Sparkle:
     url: https://github.com/sparkle-project/Sparkle
     from: "2.6.0"
   ```
   and add `- package: Sparkle` (product `Sparkle`) to the `Lumitext` target deps.
2. Generate keys: `./bin/generate_keys` (from Sparkle) → put the **public** key in
   `App/Info.plist` as `SUPublicEDKey`; keep the private key in your login keychain.
3. Add to `App/Info.plist`:
   `SUFeedURL` = the raw URL of `appcast.xml`, `SUEnableAutomaticChecks` = `true`.
4. Wire a `SPUStandardUpdaterController` and a "Check for Updates…" `CommandGroup`
   in `LumitextApp` (a ready-to-paste `App/Updates/UpdatesController.swift` is described
   in `docs/adr/0002-distribution-and-updates.md`).
5. `sign.sh` already signs `Contents/Frameworks/*` first, so the embedded
   `Sparkle.framework` (and its `Autoupdate`/`Updater.app`) get signed correctly.
6. Per release: `generate_appcast <dir-with-DMG>` produces the `<item>` (incl.
   `sparkle:edSignature`); paste it into `distribution/appcast.xml` and publish.

Because the screensaver is an `.appex` embedded in the app, a single Sparkle update
refreshes both the GUI and the saver. After an update, the app re-runs `pluginkit -a`
on next launch to refresh registration.
