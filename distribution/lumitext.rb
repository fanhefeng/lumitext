# Homebrew cask for Lumitext.
#
# Until Lumitext is in the official homebrew-cask tap, install from this repo:
#   brew install --cask fanhefeng/tap/lumitext           # via a custom tap, or
#   brew install --cask ./distribution/lumitext.rb       # directly from a clone
#
# The `version`, `sha256`, and `url` are filled in at each release (see RELEASE.md).
# `auto_updates true` tells Homebrew that the app updates itself via Sparkle, so
# `brew upgrade` won't fight the in-app updater.
cask "lumitext" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256_AT_RELEASE"

  url "https://github.com/fanhefeng/lumitext/releases/download/v#{version}/Lumitext-#{version}.dmg",
      verified: "github.com/fanhefeng/lumitext/"
  name "Lumitext"
  desc "Custom-text screensaver for macOS Tahoe"
  homepage "https://github.com/fanhefeng/lumitext"

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Lumitext.app"

  uninstall quit:      "io.github.fanhefeng.lumitext",
            pkgutil:   "io.github.fanhefeng.lumitext"

  zap trash: [
    "~/Library/Group Containers/group.io.github.fanhefeng.lumitext",
    "~/Library/Containers/io.github.fanhefeng.lumitext",
  ]
end
