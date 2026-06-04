# ADR-0001: ExtensionKit `.appex` saver + shared-directory config channel

Status: Accepted; **config channel REVISED 2026-06-04** (App Group → /Users/Shared/Lumitext, see Addendum)

## Context

We need a custom-text screensaver for macOS Tahoe that is (a) configurable from a
real GUI, (b) publishable, (c) robust against the known Tahoe `legacyScreenSaver`
bugs. The design plan (PLAN.md) chose a modern ExtensionKit `.appex` saver embedded
in a host app, with configuration shared via an App Group container. M1 was the
go/no-go spike to verify the two load-bearing technical unknowns on real hardware.

## What M1 empirically verified (macOS 26.5, this machine)

Evidence: unified-log capture of the live `LumitextSaver` appex process (PID 63618),
hosted by `com.apple.wallpaper.agent`, running as a real screensaver.

1. **Private ScreenSaver appex API works on Tahoe 26.5.** Subclassing the
   undocumented `ScreenSaverExtension` (principal class) and
   `ScreenSaverViewController` via the bridging header compiles against the 26.5 SDK
   and runs: `LumitextExtension.init()` and `LumitextViewController.loadView()` both
   fired. No missing symbols, no notarization needed for ad-hoc dev.
2. **The appex renders full-screen as a real saver.** `loadView()` received the true
   display frame (1512×982 backing points), and our frame-width `isPreview` heuristic
   correctly returned `false` for the full-screen case (we never trust the OS
   `isPreview`, per FB19201567).
3. **The sandboxed appex resolves the App Group container.** The process is sandboxed
   (`libsystem_secinit AppSandbox`), and
   `container_create_or_lookup_app_group_path_by_app_group_identifier` returned
   **success** for `group.io.github.fanhefeng.lumitext` with `euid=501, uid=501` —
   i.e. the same per-user container the (uid-501) host app writes. This is the hard,
   Tahoe-specific unknown, and it is confirmed.
4. **Toolchain/packaging is sound.** Ad-hoc `codesign` accepts the `application-groups`
   entitlement; `pluginkit -a` registers the appex; it appears under "User
   Screensavers" in `papersaver list` and can be set active via PaperSaverKit.

## Not yet directly observed (high confidence by standard semantics)

- **App Group file READ of host-written config from inside the saver sandbox.** Once
  the container resolves (it did, #3), reading/writing files inside it is universal
  App Sandbox behavior, not Tahoe-specific. The probe build that would have logged the
  exact read result couldn't get a clean run because the dev trigger wedged the
  screensaver subsystem (see below). **Re-verified end-to-end in M3** after a host
  reboot heals the dev wedge.
- **`/Users/Shared` read DENIED from the appex sandbox** (the negative control).
  Documented by research and by Apple's own savers carrying a
  `temporary-exception.files.absolute-path.read-only=/` entitlement a third party
  cannot notarize. We therefore do **not** use `/Users/Shared` as a production channel.

## Decision

Proceed exactly as planned:
- Saver = ExtensionKit `.appex` (NOT legacy `.saver`).
- Config channel = **App Group container** `group.io.github.fanhefeng.lumitext`
  (host app = sole writer; appex = reader). No `ScreenSaverDefaults`, no `/Users/Shared`
  production path.
- `SSEHasConfigureSheet=false`, `SSENeedsAnimationTimer=false`; config lives 100% in the host app.

## Addendum (2026-06-04): App Group channel REJECTED by Tahoe TCC → /Users/Shared

In real user testing the saver rendered only defaults. Live diagnosis found
`containermanagerd` rejecting every group-container request from the saver:

> `[io.github.fanhefeng.lumitext.saver] requesting [group.io.github.fanhefeng.lumitext]:
> REJECTED. Requestor's signature does not allow it to access a TCC-protected group
> container. Group containers identifiers should be prefixed by requestor's team ID.`

On Tahoe, group containers are TCC-protected: access is auto-granted only when the
group ID is prefixed with the requestor's **Team ID**. Ad-hoc dev signing has no Team
ID → flat rejection (a screensaver has no UI context for a consent prompt). The
earlier M1/M3 successes rode a stale pre-enforcement lease — a false positive.

**Revised channel:** the host writes `/Users/Shared/Lumitext/config.json`; the saver
reads it via a **scoped** `com.apple.security.temporary-exception.files.absolute-path.read-only`
for `/Users/Shared/Lumitext/`. This is Aerial v4's shipped-and-notarized pattern
(theirs is even broader: read "/" + read-write /Users/Shared). Corrections to the
original analysis:

- "A third party cannot notarize temporary-exception entitlements" was **wrong** —
  notarization does not police entitlements; only Mac App Store review does, and we
  are not MAS. Aerial v4 ships exactly this.
- The App Group channel can be revisited once a real Team ID exists (use a
  team-prefixed ID, e.g. `TEAMID.lumitext`), trading world-readability for container
  privacy. The host migrates any legacy group-container config on first launch.
- The saver also no longer waits on `containermanagerd` at startup: the read is a
  plain sandboxed file read (instant). The saver renders a TEXTLESS background first
  and swaps the loaded config in — never flashes wrong placeholder text.

## Consequence / operational hazard discovered (important)

Driving the saver in dev via `open -a ScreenSaverEngine` then `pkill ScreenSaverEngine`
(SIGTERM mid-session) **corrupts loginwindow's `SACScreenSaverIsRunning` flag**
(stuck at 1 → every later launch logs "Screen Saver Already Running; Exiting") and,
because the persona-context saver had the App Group container open when killed, leaves
`containermanagerd_system` with a wedged lease for that one container (directory
`readdir`/writes hang; `stat` and exact-path `ENOENT` still return). Neither is fixable
without a privileged daemon restart or a logout/reboot; both are isolated to this app
and self-heal on next login. **Dev policy (see CLAUDE.md): never SIGTERM/SIGKILL the
screensaver engine; use the host app's embedded live preview as the primary rendering
verification surface, and the System Settings preview / real idle for occasional
end-to-end checks.**
