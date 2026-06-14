# Lumitext

A custom-text screensaver for macOS Tahoe (26). Type any text — pick the font,
weight, size, color, and position — and it shows as your screensaver, with a live
preview that matches exactly what you'll see.

**Features**

- Any text in any installed font — pick weight, size, color, line spacing, and on-screen position (a 9-way grid).
- True WYSIWYG live preview: the editor draws with the *same* renderer as the screensaver.
- Resolution-independent — one config looks proportionally identical on a laptop, a 6K display, and the System Settings thumbnail.
- Built-in contrast check — warns before you save text that would be invisible on its background.
- Light/dark style presets to start from.
- Standard, per-environment file locations, openable from the menu bar.
- Localized in English and 简体中文 (zh-Hans).

> **Status:** in active development (pre-release). Built and verified on macOS 26.5.

![Lumitext configuration window](docs/images/config-window.png)

## Why

macOS has no built-in way to show your own styled text as a screensaver. The native
Lock Screen "message" is a single line of unstyled plain text; the built-in *Message*
screensaver offers no real font/color/size control; and nothing on the App Store or
GitHub renders free-form, fully styled text as a true idle screensaver. Lumitext fills
that gap.

## How it works

Lumitext ships as a normal app that embeds a modern **ExtensionKit screensaver**
(`.appex`, the same format Apple's own screensavers use on Sonoma and later — not the
buggy legacy `.saver` plug-in). You configure everything in the app; the app writes a
small config to **`/Users/Shared/Lumitext/config.json`**; the sandboxed screensaver
reads that exact file through a scoped read-only entitlement (the same shipped pattern
Aerial uses — App Group containers are rejected by Tahoe's TCC for this setup, see
[ADR-0001](docs/adr/0001-appex-with-app-group-config.md)). The app's live preview and
the screensaver use the *same* rendering code, so the preview is true WYSIWYG.

```
Lumitext.app  ──writes──▶  /Users/Shared/Lumitext/config.json  ──reads──▶  LumitextSaver.appex
   (config GUI + preview)     (host = sole writer)        (scoped read-only, renders on idle)
        └──────────────── shared SwiftUI renderer (LumitextCore) ──────────────────┘
```

### About "lock screen"

A third-party screensaver renders during the **idle period before macOS secures the
lock screen** — exactly the window every screensaver (including Apple's) runs in. Once
the Mac is truly locked, macOS's login window owns the display and no third-party code
can draw there; that's an OS security boundary, not a Lumitext limitation. Lumitext
explains this in-app and lets you set the idle ("start screensaver") delay; for the
longest visible time, set your system's "require password" delay (System Settings →
Lock Screen) to begin a little after the screensaver starts.

## Files & folders

Lumitext keeps its files in standard macOS locations, and **Debug builds use a
separate set** (suffixed `-Dev`, config under a `dev/` subdirectory) so iterating on
a development build never reads or overwrites the data a shipped install owns — and
vice versa. The build environment is fixed at compile time (`#if DEBUG`); the host
app and the embedded saver are built together, so they always agree.

Open any of these from the app: **menu bar → Lumitext → Open Folder ▸**.

| What | Release (production) | Debug (development) |
|---|---|---|
| Config channel (`config.json`) | `/Users/Shared/Lumitext/` | `/Users/Shared/Lumitext/dev/` |
| Logs | `~/Library/Logs/Lumitext/` | `~/Library/Logs/Lumitext-Dev/` |
| Cache | `~/Library/Caches/Lumitext/` | `~/Library/Caches/Lumitext-Dev/` |
| Application Support | `~/Library/Application Support/Lumitext/` | `~/Library/Application Support/Lumitext-Dev/` |

The config channel stays under `/Users/Shared/Lumitext/` in both environments because
the sandboxed saver's read-only entitlement is scoped to that path — the Debug
variant is a `dev/` **subdirectory** of it (a sibling would fall outside the
exception and the dev saver couldn't read its own config).

**Logs.** The host app writes a rotating text log to
`lumitext.log` in its Logs folder above (one `.1` backup, capped at a few MB). The
**screensaver** process is sandboxed and cannot write files, so its diagnostics go
only to the unified system log — view both (host + saver) with:

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info --debug
```

## Requirements

- macOS Tahoe (26.0+). Tahoe-only by design — it uses the modern screensaver extension
  point and is built against the macOS 26 SDK.

## Install

Pre-built signed releases (DMG + Homebrew cask) will be published once the project
reaches its first tagged release. For now, build from source (below).

Sharing an unsigned preview build with someone: `./scripts/make-share-zip.sh
build/Debug/Lumitext.app` (the build `dev-build-install.sh` produces) creates a zip
containing the app plus step-by-step
install/unblock instructions (`distribution/安装说明.txt`). Recipients need macOS 26+;
hand-offs via USB/scp open with no prompts, downloads need one Gatekeeper approval
(both paths are covered in the bundled instructions).

### Installation notes

- **It must run from `/Applications`.** pluginkit caches discovered locations and prefers `/Applications`; running from elsewhere (Downloads, DerivedData) makes macOS load the wrong copy. The app detects this and offers to move itself there.
- **Quit Lumitext before replacing the bundle** — swapping a live bundle leaves stale code running and confuses LaunchServices. `dev-build-install.sh` handles this for you.
- **Ad-hoc (unsigned) builds aren't notarized.** A *downloaded* copy needs one Gatekeeper approval (right-click → Open, or System Settings → Privacy & Security → Open Anyway); copies handed over by USB/scp open with no prompt.
- **System Settings caches screensaver thumbnails aggressively.** If the thumbnail looks stale after re-installing, fully quit and reopen System Settings.

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/fanhefeng/lumitext.git
cd lumitext
swift test --package-path Packages/LumitextCore      # run core unit tests
./scripts/dev-build-install.sh                        # build, sign (ad-hoc), install to /Applications
```

Then open **System Settings → Screen Saver**, pick **LumitextSaver**, and configure the
text in the Lumitext app. See [`CLAUDE.md`](CLAUDE.md) for the full dev loop,
[`PLAN.md`](PLAN.md) for the architecture and roadmap, and
[`docs/project-overview.md`](docs/project-overview.md) for a guided tour of the codebase.

## Using Lumitext

The app must live in **/Applications** (it offers to move itself there, and won't
activate from anywhere else).

1. **Activate it.** In the Lumitext app, use the **activate** control to set it as your
   screen saver on every display — or pick **LumitextSaver** by hand in System Settings →
   Screen Saver.
2. **Edit your text.** Type in the app and choose font, weight, size, color, line
   spacing, and position. The preview updates live and matches the real screensaver
   exactly; changes autosave.
3. **Set the idle delay.** Choose how long macOS waits before starting the screensaver.
   For the longest visible time, set System Settings → Lock Screen → "require password"
   to begin a little *after* the screensaver starts (see [About "lock
   screen"](#about-lock-screen) above).

**Good to know**

- **Fonts in the screensaver.** The sandboxed saver can only read fonts from
  `/System/Library/` and `/Library/Fonts/`. A font installed just for your user
  (`~/Library/Fonts`) shows in the app's preview but **falls back to the system font in
  the actual screensaver** — the app flags such fonts with a warning.
- **Contrast.** If your text would be nearly invisible on its background, the app warns
  you before saving.
- **"Couldn't read its settings" on screen.** If the screensaver shows that note
  instead of your text, open the Lumitext app once to repair the config — a read
  failure deliberately never masquerades as your text being lost.

## Project layout

| Path | What |
|---|---|
| `App/` | SwiftUI host app — config GUI, live preview, activation |
| `Saver/` | The `.appex` screensaver (private ScreenSaver API via bridging header) |
| `Packages/LumitextCore/` | Shared config model, store, and SwiftUI renderer (+ tests) |
| `scripts/` | Build / sign / package tooling |
| `docs/adr/` | Architecture decision records |

## License

MIT — see [LICENSE](LICENSE).
