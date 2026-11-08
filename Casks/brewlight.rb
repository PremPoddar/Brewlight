cask "brewlight" do
  version "1.1.0"
  # sha256 of the 1.1.0 DMG once the release build is done; :no_check until then.
  sha256 :no_check

  url "https://github.com/PremPoddar/Brewlight/releases/download/v#{version}/Brewlight.dmg"
  name "Brewlight"
  desc "Spotlight-style manager for Homebrew packages"
  homepage "https://prempoddar.github.io/Brewlight/"

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
