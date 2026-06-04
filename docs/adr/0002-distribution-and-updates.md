# ADR-0002: Distribution & updates

Status: Accepted (tooling built in M5; Sparkle deferred to first signed release)

## Context

Lumitext must reach the public with low install friction and a self-update story, on a
codebase that (a) uses the private ScreenSaver appex API and (b) installs an App-Group
+ screensaver — both disqualifying for the Mac App Store.

## Decision

- **Channel:** Developer-ID-signed, notarized, double-stapled **DMG** as the primary
  artifact, served from **GitHub Releases**; a **Homebrew cask** (`auto_updates true`)
  as the secondary. No Mac App Store.
- **Why DMG over zip:** once notarized + stapled, the DMG (and the app inside) passes
  Gatekeeper with no prompts, online or offline — the canonical low-friction macOS
  install. Correction (2026-06-04, verified): an app dragged out of a *quarantined* DMG
  still inherits the quarantine xattr, so a DMG has **no** Gatekeeper advantage over a
  zip until it is notarized. For pre-notarization preview sharing, a `ditto -c -k` zip
  with an intact ad-hoc signature is the safer artifact (a broken signature removes the
  "Open Anyway" option entirely); see `distribution/安装说明.txt`.
- **Signing order:** inside-out — frameworks/dylibs (incl. Sparkle) → embedded
  `.appex` → outer `.app`, all with hardened runtime + secure timestamp. Implemented in
  `scripts/sign.sh`.
- **Updates:** **Sparkle 2** embedded in the host app. Because the saver is an `.appex`
  inside the app, one Sparkle update refreshes both; the app re-runs `pluginkit -a` after
  update. Deferred to the first signed release because Sparkle needs a Developer ID (to
  sign the embedded framework) and a published appcast + EdDSA key to function — none of
  which exist pre-release. Full enable steps in `RELEASE.md`.

## Ready-to-paste UpdatesController (enable per RELEASE.md step 4)

```swift
// App/Updates/UpdatesController.swift
import SwiftUI
import Sparkle

@MainActor
final class UpdatesController: ObservableObject {
    let updater: SPUStandardUpdaterController
    init() {
        // startingUpdater: true begins periodic checks (governed by SUEnableAutomaticChecks).
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}

// In LumitextApp:
//   @StateObject private var updates = UpdatesController()
//   .commands {
//       CommandGroup(after: .appInfo) {
//           Button("Check for Updates…") { updates.updater.updater.checkForUpdates() }
//       }
//   }
```

## Consequences

- The release is a 6-step, mostly-scripted process (`RELEASE.md`), gated only on the
  owner's Apple Developer Program + Developer ID + notary credential (PLAN.md M0,
  currently deferred by owner choice).
- Until then, `scripts/sign.sh` runs ad-hoc for local mechanics testing (verified), and
  `scripts/make-dmg.sh` produces a working DMG (verified). The only unrunnable step
  without the account is real notarization.
