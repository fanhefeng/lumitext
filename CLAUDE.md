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

pluginkit caches discovered locations and prefers `/Applications` — installing
anywhere else (or leaving stale DerivedData copies around) loads the WRONG build.
Always:

```bash
osascript -e 'tell application "Lumitext" to quit'   # MUST quit first — see below
rm -rf /Applications/Lumitext.app
cp -R build/Debug/Lumitext.app /Applications/
pluginkit -a /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex
pluginkit -m -v -p com.apple.screensaver | grep -i lumitext   # verify registration
```

**Never replace the bundle while Lumitext.app is running** (learned 2026-06-04):
repeated rm/cp cycles under a live instance wedged the per-session PlugInKit state —
`pluginkit -a` started silently no-opping (no pkd log lines, registration invisible
from ANY path), and neither `pluginkit -r`, `lsregister -f`, nor restarting pkd
recovered it. Only logout/re-login clears it. The same lag is why
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
