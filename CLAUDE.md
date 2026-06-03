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
rm -rf /Applications/Lumitext.app
cp -R build/Debug/Lumitext.app /Applications/
pluginkit -a /Applications/Lumitext.app/Contents/PlugIns/LumitextSaver.appex
pluginkit -m -v -p com.apple.screensaver | grep -i lumitext   # verify registration
```

## Activate & trigger without GUI

```bash
# papersaver CLI (built from /tmp/lumitext-refs/PaperSaver): set active saver
papersaver set "Lumitext"   # or PaperSaverKit.setScreensaverEverywhere from the host app
# trigger the screensaver immediately:
open -a ScreenSaverEngine
# stop it:
pkill ScreenSaverEngine
```

## Logs (primary verification channel)

```bash
log show --last 3m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info --debug
# sandbox denials from the saver process:
log show --last 3m --predicate 'process == "LumitextSaver"' --info
```

## Gotchas (verified, see PLAN.md for sources)

- Saver appex is sandboxed: config channel is the App Group container
  (`group.io.github.fanhefeng.lumitext`); `/Users/Shared` is NOT readable from
  the appex; `ScreenSaverDefaults` is a ByHost-container trap — never use it.
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
