# Homebrew cask for Lumitext.
#
# Until Lumitext is in the official homebrew-cask tap, install from this repo:
#   brew install --cask fanhefeng/tap/lumitext           # via a custom tap, or
#   brew install --cask ./distribution/lumitext.rb       # directly from a clone
#
# The `version`, `sha256`, and `url` are filled in at each release (see RELEASE.md).
#
# NOTE: do NOT add `auto_updates true` until the app actually ships a working
# in-app updater (Sparkle is deferred — ADR-0002). With it set while no updater
# exists, `brew upgrade` would skip the cask AND the app can't self-update:
# every brew user would be stranded on their installed version forever.
cask "lumitext" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256_AT_RELEASE"

  url "https://github.com/fanhefeng/lumitext/releases/download/v#{version}/Lumitext-#{version}.dmg",
      verified: "github.com/fanhefeng/lumitext/"
  name "Lumitext"
  desc "Custom-text screensaver"
  homepage "https://github.com/fanhefeng/lumitext"

  depends_on macos: :tahoe

  app "Lumitext.app"

  # No pkgutil stanza: Lumitext installs by drag, never via an installer .pkg.
  uninstall quit: "io.github.fanhefeng.lumitext"

  caveats <<~EOS
    The screensaver registers itself the first time you open the app:
      open Lumitext, set your text, then click "Set as Screen Saver".
    Until that first launch, LumitextSaver won't appear in
    System Settings → Screen Saver.
  EOS

  zap trash: [
    # The real config channel (host-written, saver-read; see ADR-0001 addendum).
    "/Users/Shared/Lumitext",
    # The sandboxed saver appex's container (keyed by the appex bundle ID; the
    # non-sandboxed host has none).
    "~/Library/Containers/io.github.fanhefeng.lumitext.saver",
    # Dev-era App-Group leftovers (never shipped; cleaned up for tidiness).
    "~/Library/Group Containers/group.io.github.fanhefeng.lumitext",
  ]
end
