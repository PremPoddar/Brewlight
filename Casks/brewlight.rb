cask "brewlight" do
  version "1.2.0"
  # shortcut: sha256 is still 1.1.0's until the v1.2.0 DMG is published; replace right after tagging
  sha256 "089fbd3e7ea75bc69a9ea2d408500f1885ce47fc4f09e92931b0be1eab80c01f"

  url "https://github.com/PremPoddar/Brewlight/releases/download/v#{version}/Brewlight.dmg"
  name "Brewlight"
  desc "Spotlight-style manager for Homebrew packages"
  homepage "https://prempoddar.is-a.dev/Brewlight/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Cask installs update through `brew upgrade --cask brewlight`; the app detects this channel
  # and does not self-update, so auto_updates stays false.
  depends_on macos: :tahoe

  app "Brewlight.app"

  zap trash: [
    "~/Library/Application Support/Brewlight",
    "~/Library/Caches/com.prempoddar.brewlight",
    "~/Library/Logs/Brewlight",
    "~/Library/Preferences/com.prempoddar.brewlight.plist",
  ]

  caveats <<~EOS
    Brewlight is not notarized yet. The first time you open it, macOS blocks it:
    go to System Settings > Privacy & Security and click Open Anyway.
  EOS
end
