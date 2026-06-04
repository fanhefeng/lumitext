# Lumitext — agent notes

macOS Tahoe (26.x)-only custom-text screensaver. Host app `Lumitext.app` embeds the
ExtensionKit screensaver `LumitextSaver.appex` (modern `com.apple.screensaver`
extension point — NOT a legacy `.saver`). Full architecture & milestone plan: `PLAN.md`.
Key decisions are recorded in `docs/adr/`.

## Build

The `.xcodeproj` is generated — never edit or commit it. After changing `project.yml`:

```bash
xcodegen generate
xcodebuild -project Lumitext.xcodeproj -scheme Lumitext -configuration Debug build SYMROOT=$PWD/build
```

Dev signing is ad-hoc (`CODE_SIGN_IDENTITY=-`, no team). Release signing comes via
`scripts/sign.sh` once the owner has a Developer ID (deferred — see PLAN.md M0).

## Install & register (dev loop)

**Use `scripts/dev-build-install.sh` — never raw `xcodebuild` + `cp`.** The Xcode
project intentionally carries NO `CODE_SIGN_ENTITLEMENTS` (it would demand a
provisioning profile ad-hoc signing can't provide); the script post-signs the appex
with `Saver/LumitextSaver.debug.entitlements`. An appex signed WITHOUT
`com.apple.security.app-sandbox` is **silently filtered out of pkd discovery**
(verified 2026-06-04): `pluginkit -a` exits 0 but is a no-op, and pkd logs
`LS reported 0 plug-ins`. Recovery for an already-installed unsigned copy —
re-sign in place, then re-register:

```bash
codesign --force --sign - --entitlements Saver/LumitextSaver.debug.entitlements \
    /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex
codesign --force --sign - --entitlements App/Lumitext.entitlements /Applications/Lumitext.app
pluginkit -a /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex
pluginkit -m -v -p com.apple.screensaver | grep -i lumitext   # verify registration
```

pluginkit caches discovered locations and prefers `/Applications` — installing
anywhere else (or leaving stale DerivedData copies around) loads the WRONG build.
Quit Lumitext.app (`osascript -e 'tell application "Lumitext" to quit'`) before
replacing the bundle.

**pkd debugging notes** (verified 2026-06-04):
- pkd lives in launchd's **user domain**, so it SURVIVES logout/re-login (the
  earlier "only logout clears it" wedge diagnosis was wrong — that incident was
  almost certainly the missing-entitlements no-op above). SIP blocks
  `launchctl kickstart`, but a plain `kill -TERM $(pgrep -x pkd)` is safe: launchd
  respawns it on demand. (This is NOT ScreenSaverEngine — that stays forbidden.)
- zsh has a `log` builtin — use `/usr/bin/log stream` or predicates silently break.
- `pluginkit -a` always exits 0; the ONLY truth is the `pluginkit -m` query plus
  `/usr/bin/log stream --predicate 'process == "pkd"' --info --debug` (look for
  "Candidate plugin count from LaunchServices"). The discovery lag is why
  `ActivationManager.activate()` polls discovery between register and activate.

## Activate & trigger — SAFE policy (read this; learned the hard way)

**NEVER `pkill`/`kill` ScreenSaverEngine or the saver process, and never SIGTERM a
running `SACScreenSaverStartNow`.** Killing the engine mid-session corrupts
loginwindow's `SACScreenSaverIsRunning` flag (stuck at 1 → "Screen Saver Already
Running; Exiting" forever) AND wedges the App Group container's `containermanagerd`
lease (directory reads hang). Both need a logout/reboot to clear. This is the Tahoe
screensaver fragility the research warned about — don't poke it.

Primary rendering verification = **the host app's embedded live preview**
(`NSHostingView` of the same `LumitextCore` SwiftUI view). It runs in a normal process,
needs no engine, and is byte-identical to what the saver draws. Use it for almost all
dev iteration.

Occasional real end-to-end check (saver reads host config in its true sandbox):
```bash
papersaver set-saver "LumitextSaver"     # set active (PaperSaver CLI)
# Then trigger via System Settings > Screen Saver preview, OR wait for real idle.
# To recover the screen, move the real mouse / press a key — do NOT pkill.
# When done testing, restore the user's saver:  papersaver set-saver "Hello"
```

If the screensaver subsystem is already wedged (isRunning stuck / container readdir
hangs): the only clean fix is **log out & back in, or reboot**. App Group file I/O by
exact path still works while wedged; only directory enumeration hangs.

## Logs (primary verification channel)

```bash
log show --last 3m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info --debug
# sandbox denials from the saver process:
log show --last 3m --predicate 'process == "LumitextSaver"' --info
```

## Gotchas (verified, see PLAN.md for sources)

- Saver appex is sandboxed: config channel is `/Users/Shared/Lumitext/config.json`
  (host writes; saver reads via a scoped read-only temporary-exception entitlement —
  Aerial v4's shipped pattern). App Group containers are REJECTED by Tahoe's TCC
  unless the group ID is Team-ID-prefixed (impossible with ad-hoc signing) — see
  ADR-0001 addendum. `ScreenSaverDefaults` is a ByHost-container trap — never use it.
- `isPreview` from the OS is unreliable on Tahoe (FB19201567) — use the
  frame-width heuristic (< 400pt = preview).
- System Settings "Options…" button is broken on Tahoe — `SSEHasConfigureSheet`
  stays `false`; all config lives in the host app.
- Thumbnail imageset (107x65 / 214x130) is mandatory or the saver won't appear
  in System Settings. Regenerate via `swift scripts/make-thumbnail.swift`.
- System Settings caches saver thumbnails/registration aggressively: re-register
  with `pluginkit -a`, then fully quit & reopen System Settings.

## Reference repos (cloned, read-only)

`/tmp/lumitext-refs/{AppexSaverMinimal,ScreenSaverMinimal,PaperSaver,Aerial}` —
AppexSaverMinimal is the structural template (MIT); Aerial is the production
appex precedent; PaperSaver provides activation APIs + CLI.
