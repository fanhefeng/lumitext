# Post-reboot verification checklist

During M1 development, a dev-trigger (`pkill` of the screensaver engine mid-session)
wedged two pieces of macOS state that only a **logout/restart** clears:

1. `loginwindow`'s `SACScreenSaverIsRunning` flag is stuck at 1 ("Screen Saver Already
   Running; Exiting" on launch).
2. The App Group container `~/Library/Group Containers/group.io.github.fanhefeng.lumitext`
   has a wedged `containermanagerd` lease — directory *enumeration* hangs (exact-path
   file I/O still works).

Both are dev-environment artifacts (not product bugs — see `docs/adr/0001`), isolated to
this app, and harmless to other apps. **After your next reboot/login**, run these to
complete the live verification that was deferred. None of it requires a Developer ID.

```bash
# 0. confirm the wedge cleared
ls "$HOME/Library/Group Containers/group.io.github.fanhefeng.lumitext"   # should list instantly

# 1. rebuild + install fresh
cd /Users/fhf/IT/code/mac-screen-text
./scripts/dev-build-install.sh

# 2. verify the saver reads host-written config end-to-end
#    a) open Lumitext.app, change the text/color/size, quit (autosaves to the container)
#    b) confirm the config landed:
cat "$HOME/Library/Group Containers/group.io.github.fanhefeng.lumitext/config.json"

# 3. live screensaver test (DO NOT pkill the engine — see CLAUDE.md)
papersaver=/tmp/lumitext-refs/PaperSaver/.build/release/papersaver
"$papersaver" set-saver "LumitextSaver"
#    Trigger via System Settings > Screen Saver preview, or a hot corner, or real idle.
#    Expect: your styled text full-screen. Move the real mouse to exit.
#    Restore afterward:  "$papersaver" set-saver "Hello"

# 4. multi-monitor (if you have a second display): trigger and confirm text on BOTH,
#    each independent, no instance pile-up:
log show --last 2m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info | grep -iE "setupHosting|deinit"
```

Expected results: config round-trips through the container; the saver shows your text
on every display; clean init/teardown per activation (no leaked instances). If all pass,
the architecture is fully validated on real hardware end-to-end.
