# Remaining verification

## ✅ Already live-verified on macOS 26.5 (2026-06-04)

The core architecture is proven end-to-end on real hardware:

- The sandboxed `.appex` saver loads and runs as a real screensaver (private
  ScreenSaver API works on Tahoe).
- It **reads the exact config the host wrote**, from the shared App Group container —
  confirmed via the unified log from the live saver process:
  ```
  applied config path=…/Group Containers/group.io.github.fanhefeng.lumitext/config.json size=234
  ```
- The renderer output (default / CJK / colors / alignment / preview-miniature) and the
  full host UI were verified by image snapshots.

A dev-trigger had briefly wedged the screensaver subsystem during M1; it self-healed
(leases timed out) and the live verification above was completed afterward.

## Still worth checking (optional, needs specific conditions)

1. **Multi-monitor** (needs a second display): trigger the screensaver and confirm the
   text renders independently on BOTH displays with no instance pile-up:
   ```bash
   /tmp/lumitext-refs/PaperSaver/.build/release/papersaver set-saver "LumitextSaver"
   # trigger via a hot corner or real idle; move the real mouse to exit (never pkill)
   log show --last 2m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info \
     | grep -iE "applied config|deinit"
   /tmp/lumitext-refs/PaperSaver/.build/release/papersaver set-saver "Hello"   # restore
   ```
2. **Clean-account install** (part of the release runbook, RELEASE.md): after the first
   notarized DMG, drag-install on a second account and confirm no Gatekeeper prompt and
   the saver appears in System Settings.

## Dev reminder

Never `pkill`/SIGTERM the screensaver engine or saver — it wedges loginwindow's
`isRunning` flag and the container lease until logout/reboot. Exit the screensaver with
real input (mouse/keyboard). See `CLAUDE.md` and `docs/adr/0001`.
