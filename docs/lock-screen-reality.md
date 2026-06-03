# The "lock screen" reality (read before promising it)

Users often ask for text "on the lock screen." On macOS this means two different things,
and only one is achievable by a third-party app. Lumitext is honest about which.

## Two surfaces

1. **The idle screensaver** — what shows after the Mac is idle for a while, *before* it
   secures itself. This is where every screensaver (Apple's and third-party) draws.
   **Lumitext renders here.** ✅
2. **The secured lock screen** — the password/Touch-ID screen shown once the Mac is
   actually locked. This is owned by `loginwindow` in a separate, privileged context.
   Only an Apple `SFAuthorizationPluginView` (used by enterprise auth plugins) can draw
   there; `loginWindowModulePath` excludes non-Apple savers. **No third-party app —
   including Lumitext — can render here.** ❌ (Verified via Apple DTS thread 654383.)

## What Lumitext does about it

- It renders your styled text as the **idle screensaver**, full-screen, on every display.
- In the app, the **idle delay** ("Start after") controls how soon your text appears.
- The honest framing in the app's "About lock screen" panel: to maximize the time your
  text is visible, set the system's **"require password" delay to begin a little after**
  the screensaver starts. During that grace window your text is on screen; after it, the
  OS lock takes over (as it must, for security).

## What we must NOT claim

- ❌ "Replaces your lock screen with custom text."
- ❌ "Shows your text while the Mac is locked."
- ✅ "A beautiful custom-text screensaver that the Mac still locks normally afterward."

This file is the source of truth for product/marketing copy on the topic.
