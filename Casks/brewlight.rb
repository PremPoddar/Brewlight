# Template for the Homebrew cask. scripts/release.sh prints the version and sha256 lines.
cask "brewlight" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/example/brewlight/releases/download/v#{version}/Brewlight-#{version}.dmg"
  name "Brewlight"
  desc "Spotlight-style manager for Homebrew packages"
  homepage "https://github.com/example/brewlight"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Cask installs update through `brew upgrade --cask brewlight`; the app detects this channel
  # and does not self-update, so auto_updates stays false.
  depends_on macos: ">= :tahoe"

  app "Brewlight.app"

  zap trash: [
    "~/Library/Application Support/Brewlight",
    "~/Library/Caches/com.example.brewlight",
    "~/Library/Logs/Brewlight",
    "~/Library/Preferences/com.example.brewlight.plist",
  ]
end
