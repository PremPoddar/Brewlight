# Progress

Status as of 2026-10-31 (second pass: responsiveness). Build: zero warnings with Swift 6 strict concurrency (Xcode 27.1,
deployment target macOS 26.0). Tests: 36 unit tests, 4 performance tests, 1 UI smoke test, all passing.

## Done (by milestone)

1. **Skeleton** — XcodeGen project (`project.yml`), app + askpass helper + test targets, identity
   in `Config/App.xcconfig` and `AppInfo`, design-system tokens from the Brewlight design
   (light/dark/increase-contrast), main window with sidebar, Settings (7 tabs), custom About
   window, appearance switching, String Catalog, brew locator, onboarding when brew is missing.
2. **Catalog + search** — loader for Homebrew's API cache, binary snapshot, search index,
   All Packages with filters/sort (restored via scene storage), package detail.
3. **Installed state** — Cellar/Caskroom/pinned scanner with receipts, FSEvents live updates,
   async disk usage.
4. **Operations** — `BrewRunner` actor (env, line streaming, SIGINT→SIGTERM cancel), serialized
   mutating queue, activity drawer with live log/progress/retry/copy-for-bug-report,
   `SUDO_ASKPASS` helper (`BrewlightAskPass`, 2-minute timeout), stall watchdog + "Run in
   Terminal", SwiftData history.
5. **Updates** — local outdated estimate confirmed by `brew outdated --json=v2`, Updates page per
   design, upgrade one/selected/all, greedy toggle, pinning, skip version, background checks
   (`NSBackgroundActivityScheduler`, AC-only option), notifications with Upgrade All action,
   Dock badge.
6. **Dependencies** — graph model (transitive, reverse, leaves, orphans, why-installed),
   collapsible tree, Canvas graph view, dependents check before uninstall, autoremove preview.
7. **Full removal** — zap preview for casks, leftover scan for formulae, checkboxes, Trash by
   default.
8. **Icons, categories, popularity, Discover, new packages** — icon resolver (app icon →
   GitHub avatar / touch icon / favicon → monogram), bundled `categories.json` + heuristic +
   overrides, 30/90/365d analytics, trending, first-seen tracking.
9. **Taps, services, Brewfile, maintenance** — all present.
10. **Tags, favourites, notes, ⌘K palette, shortcuts** — all present. The menu bar extra from
    §5.20 was removed by decision: Brewlight is used from its window, and background update
    checks, notifications and the Dock badge cover the "glance" use case.
11. **Distribution** — channel detection (cask vs direct), `scripts/release.sh`, cask template,
    CI and release workflows.
12. **Polish** — demo mode (`-demo`), README, accessibility labels on custom controls.

## Install analytics in lists

Homebrew publishes install counts (not downloads) for 30/90/365 days. Lists can sort by
**Most Installed — 30 Days / 90 Days / Year** and **Trending**, with the value in its own column
(fixed K/M formatting, not locale compact names). Discover's "See all" opens the list ranked the
same way as the shelf (`AppModel.showAll`). Sort, type and filters live in `AppModel` and persist.
Full orders for each analytics sort are precomputed off-main when analytics load
(`Rankings.orders`), so sorting 16k packages is a ~2 ms filter, and lists are index views over the
catalog (`PackageList`) instead of copied arrays.

## Activity log and Homebrew notices

Each output line is classified once when it arrives (`LogClassifier`): errors red, `Warning:`
blocks yellow (including their continuation lines), success lines green, `==>` steps bold,
progress bars dimmed (hidden unless "Raw output"). `NoticeDetector` spots brew output that needs
a decision; today that's untrusted taps ("The following taps are not trusted"), which raises a
prompt (Trust / Untap / Learn More / Not Now, once per tap per session) and a banner in the log.
Trusting runs `brew trust --tap`. The Taps page shows trust state from `brew tap-info` and offers
Trust for untrusted taps. The drawer only auto-closes after operations with no warnings, errors
or notices.

## Maintenance, palette and search hints

- Doctor and cleanup state live in `AppModel` (`runDoctor`, `previewCleanup`, `showDoctor`,
  `showCleanup`), so the palette, toolbar menu and failure banner actually start them instead of
  only navigating. Cleanup always previews (`-n`) before anything is deleted.
- Doctor warnings show suggested fixes parsed from their text (`MaintenanceParsers.suggestions`):
  named packages (Show / Uninstall / replacement), `brew …` commands (Run, after confirming),
  `sudo …` commands (Run in Terminal, after confirming; the password goes to Terminal) and links.
  Placeholder commands such as `brew trust --formula <user>/…` are skipped.
- ⌘K: Tab (or the ⋯ button) on a package lists everything you can do with it; Esc goes back.
- The toolbar search cycles example filters in its placeholder while idle, and an ⓘ popover lists
  every filter (click to insert).

## Features adopted from other Homebrew apps (Nov 2026)

Compared against Homebrew's official BrewUI, Cork, Applite, WailBrew, Tappie and Updatest.

- **Adopt Apps** (Cork, Updatest): scans /Applications and ~/Applications (≈50 ms for 107 apps),
  matches each `.app` to the cask that installs it, and offers `brew install --cask --adopt`.
  Rows are Ready / Version differs / From the App Store (excluded from "Adopt All"); Apple's apps,
  already-managed apps and installed casks are skipped; one row per cask.
- **Exact commands everywhere** (BrewUI): actions build `BrewCommand`s first
  (`installCommands`, `uninstallCommand`, `upgradeCommands`, `adoptCommands`…); confirmation
  sheets show them and the same values run. Developer mode adds them under Upgrade All.
- **Network** (Cork, Applite, WailBrew): macOS proxy settings passed to brew as
  `http(s)_proxy`/`all_proxy`/`no_proxy`; mirror picker (TUNA, USTC, custom) sets
  `HOMEBREW_API_DOMAIN`/`HOMEBREW_BOTTLE_DOMAIN`/`HOMEBREW_BREW_GIT_REMOTE`. Extra environment
  variables still win.
- **Smart search** (Tappie): plain-language requests become filters via Apple's on-device
  Foundation Models when available (guided generation into `SmartSearchPlan`), otherwise a keyword
  mapping. Multi-word searches now rank packages by how many words they match. A banner shows
  the interpretation.
- **Deprecated or disabled** (WailBrew) section on Updates with Homebrew's reason and replacement.

Not yet verified: the on-device model path (Apple Intelligence wasn't available on the test Mac,
so only the keyword fallback was exercised) and adoption of a real app end to end.

## Versions, download cache and languages (Nov 2026)

- **Per-package download cache**: the detail view shows how much Homebrew's cache holds for a
  package (followed through its own `name--version` symlinks into `downloads/`) and clears just
  those files after listing them. Checked against the real cache (e.g. VS Code 350.5 MB).
- **Choose the active version**: when several kegs are installed (`node`, `node@22`,
  `python@3.12`…), "Make Default…" unlinks the others and links the chosen one
  (`--force` for keg-only formulae); "Remove Old Versions…" runs `brew cleanup <name>`.
  Linked state comes from `var/homebrew/linked`.
- **Translations**: German, French, Spanish, Japanese and Simplified Chinese in
  `Localizable.xcstrings` (667 strings each, category names included).
  They have not been checked by native speakers yet and are marked *needs review*; two log lines starting "Error:" stay English because the activity
  log colours by them. The app follows the system language (System Settings → General →
  Language & Region → Applications).

## Measured (Release build, real Homebrew on this Mac: 16,462 packages, 191 installed)

`Brewlight -perftour <file>` drives the real window and records how long the main thread is busy
per interaction (state change → SwiftUI update → layout → display).

| Interaction | First pass | Now |
|---|---|---|
| Type first search letter | 3,460 ms | ~33 ms |
| Later keystrokes | 60–90 ms | 8–25 ms |
| Clear search | did not finish | ~28 ms |
| Click a package | 90–170 ms (+~250 ms gesture delay) | 17–25 ms (first ~57 ms) |
| Switch to Discover | 615 ms | ~64 ms |
| Switch to Installed / All Packages | 190–250 ms | 44–67 ms |
| Switch to Services / History | 36–81 ms | 16–35 ms |
| Launch | full-screen spinner ~1.1 s | window at once; cached content ~0.3 s |
| Search per keystroke, index only | — | ~3 ms |
| Catalog index build (background) | ~2 s | ~155 ms |

What made the difference (all found with Time Profiler, not guessed):
- Window used `.automatic` resizability, so AppKit re-measured the whole SwiftUI tree for
  min/ideal/max sizes on every update → `.contentMinSize` and a `GeometryReader` root.
- Package list rebuilt (filter + sort over 16k) on every redraw, including selection clicks →
  memoized per query/filter/data version (`ListCache`, `AppModel.dataVersion`).
- `List` diffed up to 16k rows on each query change and measured row heights through
  NSTableView → lazy stack of fixed-height rows, paginated 150 at a time.
- Separate double-tap and tap gestures delayed every single click → one handler using the event's
  click count.
- Derived data (outdated minus skipped, popularity rankings, trending, new packages, counts)
  recomputed per render → stored, recomputed only when inputs change, heavy parts off-main.
- SwiftUI `Menu`s rebuilt their NSMenus on every update → menus built on click (`LazyMenuButton`).
- Toolbar content read model state, so any change re-bridged NSToolbar → each item is its own view.
- `brew` processes were spawned on the main thread → spawned on a background queue.
- Launch waited on the Cellar scan → last-known state (`state.plist`) and the installed subset
  of the catalog (`catalog-hot.plist`) load first; everything refreshes in the background.

Remaining floor: a section switch builds a new SwiftUI view tree (~16–65 ms); the first window
render takes ~0.3 s. Idle memory and scrolling haven't been measured in Instruments yet.

## Decisions and spec deviations

- **Homebrew 7 changed the API cache.** `api/formula.jws.json` and `api/cask.jws.json` no longer
  exist; there is one `api/internal/packages.<bottle_tag>.jws.json` whose payload has
  `formulae`/`casks` dictionaries with compact keys (`stable_version`, `stable_dependencies`
  with `{name: ":build"}` tags, `raw_artifacts`, `deprecate_args`, …). The loader reads that
  first and keeps the legacy array format for the remote fallback (`formulae.brew.sh/api/*.json`).
- **`brew bundle dump` has no per-section flags** in Homebrew 7, so export dumps everything and
  filters sections in-app (`Brewfile.filter`).
- **New-package seeding:** Homebrew keeps `api/formula_names.before.txt` / `formula_names.txt`
  (and cask equivalents) to print "New Formulae" after `brew update`. Diffing them seeds
  "New in Homebrew" on first launch without calling GitHub.
- **Persistence:** SwiftData for user data. The catalog isn't in SwiftData; it's an in-memory array
  plus a binary-plist snapshot, plus a small "hot" snapshot of installed packages and a
  last-known state file so launch never waits on Homebrew or the full ~640 ms decode.
- **Search** uses byte buffers + `memmem`; ranking blends popularity into the prefix tier, which is
  what makes "chrome" → `google-chrome` (not `chrome-cli`) and "rg" → `ripgrep` work on real data.
- **Colours** are defined in code (`Theme`) with light/dark/high-contrast variants via dynamic
  `NSColor`, rather than asset-catalog colour sets, to keep the design tokens in one file.
- **Removal with unchecked zap paths:** `brew --zap` can't exclude paths, so if the user unchecks
  anything (or chose permanent delete) Brewlight runs a plain uninstall and removes exactly the
  checked paths itself.
- **Third-party taps** are read from tap directories (name, desc, homepage, version scraped from
  the Ruby file); they don't have dependency data.
- **Cask channel** is detected from the Caskroom (the app artifact resolves to the running
  bundle) rather than an Info.plist marker, which a manual copy could fake. The cask template
  sets `auto_updates false`.

## Left to do

- **Sparkle 2** for the direct-download channel (needs the SPM dependency, EdDSA keys and an
  appcast). Until then "Check for Updates" opens the releases page for direct installs.
- Final icon in Icon Composer (`Design/ICON_BRIEF.md`); current icon is a generated placeholder.
- Category file updates from the repo (signed) without an app update.
- README screenshots: `-demo -snapshot <file> -screen <name>` renders the window, but system
  glass (sidebar) doesn't draw into offscreen captures, so take them with Screenshot.app instead.
- Settings toggles that are stored but not yet applied: list density, "Fetch release links from
  GitHub", "Check for app updates automatically", "Confirm before destructive actions".
- Memory and 120 Hz scrolling in Instruments, and a full VoiceOver audit; the list density
  setting is stored but not yet applied to rows.
- Context menus on list rows are still SwiftUI `.contextMenu` (cheap at ~20 visible rows, but
  could also move to on-demand NSMenus).
- Verify `SUDO_ASKPASS` end to end with a pkg-based cask on a real install.
- Manual pass of every §5 acceptance criterion on a real Homebrew setup.
- Native-speaker review of the five translations, and checking longer German strings for truncation
  (e.g. "hinzugefügt" on the narrow New in Homebrew cards).
