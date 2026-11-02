Brewlight — like Spotlight, but for brew.

A fast, native macOS app for everything you do with Homebrew: search all ~16,000 formulae and
casks as you type, see rich details, install, upgrade, pin, fully remove apps with their leftover
files, manage services and taps, explore dependency trees, and back up with Brewfiles.

Requires macOS 26 (Tahoe) or later and [Homebrew](https://brew.sh). If Homebrew isn't installed,
Brewlight walks you through installing it.

## Install

**Homebrew**

```bash
brew install --cask brewlight
```

**Direct download:** grab `Brewlight-<version>.dmg` from
[Releases](https://github.com/example/brewlight/releases) and drag Brewlight to Applications.

## Highlights

- **⌘K command palette** searches packages and actions together, per keystroke (≈3 ms across
  the full catalog on an M-series Mac). Filters: `is:installed`, `is:outdated`, `is:pinned`,
  `type:cask`, `tag:work`, `tap:hashicorp`, `cat:browsers`.
- **Instant** — opens with your last-known packages, updates and sizes straight away and
  refreshes from Homebrew in the background; reads Homebrew's own API cache and the
  Cellar/Caskroom directly instead of shelling out.
- **Safe removal** — "Remove completely" lists every file that would be deleted, with sizes
  and checkboxes, and moves them to the Trash by default.
- **Updates vs. upgrades** are labelled clearly; pinned packages and skipped versions are
  respected by Upgrade All.
- **Adopt apps** you installed yourself so Homebrew keeps them updated
  (`brew install --cask --adopt`), without reinstalling them.
- **Smart search**: describe what you need (“an app to edit videos”) and it becomes filters,
  using Apple's on-device model when available.
- **Nothing hidden**: every confirmation shows the exact `brew` command that will run.
- Proxy and download-mirror settings for networks where GitHub is slow or filtered.
- **Several versions side by side**: pick which installed version is on your PATH, and see or
  clear each package's download cache.
- Available in English, German, French, Spanish, Japanese and Simplified Chinese.
- Discover (trending, popular, new in Homebrew), categories, personal tags, favourites and
  notes, services, taps, maintenance (doctor, cleanup, disk usage) and history.

## Building

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Brewlight.xcodeproj
```

Run with `-demo` to use fixture data (no Homebrew needed). App identity — name, bundle ID,
version, cask token, repository — lives in `Config/App.xcconfig`.

Tests:

```bash
xcodebuild test -scheme Brewlight -destination 'platform=macOS'
```

Interaction timings against your real Homebrew (writes a report, then quits):

```bash
xcodebuild -scheme Brewlight -configuration Release build && open -W "$(xcodebuild -scheme Brewlight -configuration Release -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/Brewlight.app" --args -perftour /tmp/brewlight-perf.txt
```

Performance budgets are checked against an optimized build:

```bash
xcodebuild test -scheme Brewlight -configuration Release -destination 'platform=macOS' -only-testing:BrewlightTests/PerformanceTests ENABLE_TESTABILITY=YES
```

## Not affiliated

Brewlight is an independent app, not affiliated with the Homebrew project or Apple. Spotlight is
a trademark of Apple Inc. Homebrew is run by volunteers — please consider
[donating](https://github.com/Homebrew/brew#donations).
