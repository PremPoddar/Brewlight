import Foundation

/// Fixture data for `-demo` (screenshots, UI tests, Macs without Homebrew). Mirrors the design.
enum DemoData {
    static let adoptable: [AdoptableApp] = [
        AdoptableApp(path: "/Applications/Google Chrome.app", name: "Google Chrome", token: "google-chrome", appVersion: "142.0.7444.60",
                     caskVersion: "142.0.7444.60", bundleID: "com.google.Chrome", isAppStore: false),
        AdoptableApp(path: "/Applications/Zed.app", name: "Zed", token: "zed", appVersion: "0.206.1",
                     caskVersion: "0.208.4", bundleID: "dev.zed.Zed", isAppStore: false),
        AdoptableApp(path: "/Applications/Ghostty.app", name: "Ghostty", token: "ghostty", appVersion: "1.3.1",
                     caskVersion: "1.3.1", bundleID: "com.mitchellh.ghostty", isAppStore: false),
        AdoptableApp(path: "/Applications/Things3.app", name: "Things3", token: "things", appVersion: "3.22",
                     caskVersion: "3.22", bundleID: "com.culturedcode.ThingsMac", isAppStore: true)
    ]

    struct Bundle {
        var catalog: Catalog
        var installed: [InstalledPackage]
        var outdated: [String: OutdatedInfo]
        var popularity: Popularity
        var sizes: [String: Int64]
        var firstSeen: [String: Date]
        var services: [BrewService]
        var taps: [BrewTap]
        var env: BrewEnvironment
    }

    private typealias Row = (token: String, kind: PackageKind, desc: String, version: String, homepage: String, deps: [String], installs: Int)

    private static let rows: [Row] = [
        ("bat", .formula, "Clone of cat(1) with syntax highlighting and Git integration", "0.26.0", "https://github.com/sharkdp/bat", ["libgit2", "oniguruma"], 61_204),
        ("fd", .formula, "Simple, fast and user-friendly alternative to find", "10.3.0", "https://github.com/sharkdp/fd", [], 48_310),
        ("ffmpeg", .formula, "Play, record, convert, and stream audio and video", "8.0.1", "https://ffmpeg.org/", ["aom", "dav1d", "lame", "libass", "libvpx", "opus", "sdl2", "svt-av1", "x264", "x265", "webp", "libvorbis"], 187_420),
        ("gh", .formula, "GitHub command-line tool", "2.82.1", "https://cli.github.com/", [], 120_115),
        ("git", .formula, "Distributed revision control system", "2.51.1", "https://git-scm.com", ["gettext", "pcre2"], 410_877),
        ("iterm2", .cask, "Terminal emulator as alternative to Apple’s Terminal app", "3.6.5", "https://iterm2.com/", [], 52_330),
        ("jq", .formula, "Lightweight and flexible command-line JSON processor", "1.8.1", "https://jqlang.github.io/jq/", ["oniguruma"], 140_990),
        ("node", .formula, "Open-source, cross-platform JavaScript runtime environment", "24.11.0", "https://nodejs.org/", ["brotli", "c-ares", "icu4c@78", "libnghttp2", "libuv", "openssl@3"], 361_442),
        ("postgresql@17", .formula, "Object-relational database system", "17.7", "https://www.postgresql.org/", ["icu4c@78", "krb5", "openssl@3"], 48_002),
        ("python@3.13", .formula, "Interpreted, interactive, object-oriented programming language", "3.13.9", "https://www.python.org/", ["mpdecimal", "openssl@3", "sqlite", "xz"], 298_120),
        ("python@3.12", .formula, "Interpreted, interactive, object-oriented programming language", "3.12.12", "https://www.python.org/", ["mpdecimal", "openssl@3", "sqlite", "xz"], 120_400),
        ("ripgrep", .formula, "Search tool like grep and The Silver Searcher", "14.1.1", "https://github.com/BurntSushi/ripgrep", ["pcre2"], 98_771),
        ("visual-studio-code", .cask, "Open-source code editor", "1.106.0", "https://code.visualstudio.com/", [], 140_220),
        ("ghostty", .cask, "Fast, native, feature-rich terminal emulator pushing modern features", "1.3.1", "https://ghostty.org/", [], 48_200),
        ("uv", .formula, "Extremely fast Python package installer and resolver, written in Rust", "0.9.5", "https://docs.astral.sh/uv/", [], 161_000),
        ("lazygit", .formula, "Simple terminal UI for git commands", "0.55.1", "https://github.com/jesseduffield/lazygit", [], 39_500),
        ("wget", .formula, "Internet file retriever", "1.25.0", "https://www.gnu.org/software/wget/", ["libidn2", "openssl@3"], 190_440),
        ("jj", .formula, "Git-compatible distributed version control system", "0.34.0", "https://github.com/jj-vcs/jj", [], 9_100),
        ("yazi", .formula, "Blazing fast terminal file manager written in Rust", "25.5.31", "https://github.com/sxyazi/yazi", [], 12_300),
        ("television", .formula, "General purpose fuzzy finder TUI", "0.13.6", "https://github.com/alexpasmantier/television", [], 4_200),
        ("zed", .cask, "Multiplayer code editor", "0.208.4", "https://zed.dev/", [], 30_100),
        ("ripgrep-all", .formula, "ripgrep, but also PDFs, e-books, Office docs, zip…", "0.10.9", "https://github.com/phiresky/ripgrep-all", ["ripgrep"], 3_400),
        ("ripsecrets", .formula, "Prevent committing secret keys into your source code", "0.1.11", "https://github.com/sirwart/ripsecrets", [], 1_200),
        ("rip2", .formula, "Safe and ergonomic alternative to rm", "0.9.4", "https://github.com/MilesCranmer/rip2", [], 900),
        ("starship", .formula, "Cross-shell prompt for astronauts", "1.3.1", "https://starship.rs", [], 66_000),
        ("oh-my-posh", .formula, "Prompt theme engine for any shell", "26.0.0", "https://ohmyposh.dev", [], 20_000),
        ("docker-desktop", .cask, "App to build and share containerised applications and microservices", "4.49.0", "https://www.docker.com/products/docker-desktop", [], 90_000),
        ("yt-dlp", .formula, "Feature-rich command-line audio/video downloader", "2025.10.22", "https://github.com/yt-dlp/yt-dlp", ["ffmpeg", "python@3.13"], 70_000),
        ("whisper-cpp", .formula, "Port of OpenAI's Whisper model in C/C++", "1.8.2", "https://github.com/ggml-org/whisper.cpp", ["ffmpeg"], 8_000),
        ("google-chrome", .cask, "Web browser", "142.0.7444.60", "https://www.google.com/chrome/", [], 180_000)
    ]

    private static let libs = ["aom", "dav1d", "lame", "libass", "libvpx", "opus", "sdl2", "svt-av1", "x264", "x265", "webp", "libvorbis",
                               "gettext", "pcre2", "oniguruma", "libgit2", "brotli", "c-ares", "icu4c@78", "libnghttp2", "libuv", "openssl@3",
                               "krb5", "mpdecimal", "sqlite", "xz", "libidn2"]

    static func make() -> Bundle {
        var packages: [Package] = rows.map { r in
            var p = Package(kind: r.kind, token: r.token, fullName: r.token, displayName: r.token, desc: r.desc,
                            homepage: r.homepage, version: r.version, license: r.kind == .formula ? "MIT" : nil,
                            tap: r.kind == .formula ? "homebrew/core" : "homebrew/cask")
            p.dependencies = r.deps
            p.hasBottle = r.kind == .formula
            if r.token == "ripgrep" { p.aliases = ["rg"] }
            if r.token == "ffmpeg" {
                p.license = "GPL-2.0-or-later"
                p.caveats = "This build omits non-free codecs. For fdk-aac and other extras, switch to the full build:\n  brew uninstall ffmpeg && brew install ffmpeg-full"
            }
            if r.token == "postgresql@17" { p.hasService = true; p.kegOnly = true }
            if r.token == "python@3.12" { p.kegOnly = true }
            if r.token == "starship" { p.deprecationReason = "unmaintained"; p.replacement = "oh-my-posh" }
            if r.kind == .cask { p.appNames = ["\(r.token.capitalized).app"]; p.zapPaths = ["~/Library/Preferences/com.example.\(r.token).plist"] }
            return p
        }
        for lib in libs where !packages.contains(where: { $0.token == lib }) {
            var p = Package(kind: .formula, token: lib, fullName: lib, displayName: lib, desc: "Library used by other formulae",
                            homepage: "https://example.org/\(lib)", version: "1.0", tap: "homebrew/core")
            p.hasBottle = true
            packages.append(p)
        }
        packages.sort { $0.token < $1.token }

        let installedSpec: [(String, PackageKind, String, Bool)] = [
            ("bat", .formula, "0.25.0", true), ("fd", .formula, "10.3.0", true), ("ffmpeg", .formula, "8.0", false),
            ("gh", .formula, "2.81.0", true), ("git", .formula, "2.51.1", true), ("iterm2", .cask, "3.6.4", true),
            ("jq", .formula, "1.8.1", true), ("node", .formula, "24.9.0", true), ("postgresql@17", .formula, "17.6", true),
            ("python@3.13", .formula, "3.13.7", false), ("python@3.12", .formula, "3.12.12", true), ("ripgrep", .formula, "14.1.1", true),
            ("visual-studio-code", .cask, "1.105.1", true), ("starship", .formula, "1.2.0", true),
            ("docker-desktop", .cask, "4.48.0", true), ("yt-dlp", .formula, "2025.10.22", true), ("whisper-cpp", .formula, "1.8.2", true)
        ] + libs.map { ($0, PackageKind.formula, "1.0", false) }
        let installed = installedSpec.map { t, k, v, req in
            InstalledPackage(kind: k, token: t, versions: t == "node" ? ["24.8.0", v] : [v], linkedVersion: k == .formula ? v : nil,
                             installedOnRequest: req, installedAsDependency: !req, pouredFromBottle: true,
                             installedAt: Date(timeIntervalSince1970: 1_788_300_000 - Double(t.count) * 86_400),
                             runtimeDependencies: rows.first { $0.token == t }?.deps ?? [], tap: nil,
                             isPinned: t == "postgresql@17",
                             linkedIntoPrefix: k == .formula ? t != "python@3.12" : nil)
        }

        var outdated: [String: OutdatedInfo] = [:]
        for (t, k, from, to) in [("node", PackageKind.formula, "24.9.0", "24.11.0"), ("visual-studio-code", .cask, "1.105.1", "1.106.0"),
                                 ("ffmpeg", .formula, "8.0", "8.0.1"), ("python@3.13", .formula, "3.13.7", "3.13.9"),
                                 ("gh", .formula, "2.81.0", "2.82.1"), ("iterm2", .cask, "3.6.4", "3.6.5"),
                                 ("bat", .formula, "0.25.0", "0.26.0"), ("starship", .formula, "1.2.0", "1.3.1"),
                                 ("docker-desktop", .cask, "4.48.0", "4.49.0"), ("postgresql@17", .formula, "17.6", "17.7")] {
            let id = Package.id(k, t)
            outdated[id] = OutdatedInfo(id: id, kind: k, token: t, installed: from, available: to, pinned: t == "postgresql@17")
        }

        var pop = Popularity()
        for r in rows {
            let id = Package.id(r.kind, r.token)
            pop.installs30[id] = r.installs
            let growth: Double = ["ghostty": 3.12, "uv": 1.64, "lazygit": 1.41][r.token] ?? 1.0
            pop.installs90[id] = Int(Double(r.installs) * 3 / growth)
        }
        pop.fetchedAt = .now

        var firstSeen: [String: Date] = [:]
        for p in packages { firstSeen[p.id] = .distantPast }
        for (t, k, days) in [("jj", PackageKind.formula, 2.0), ("yazi", .formula, 3), ("television", .formula, 5), ("zed", .cask, 6)] {
            firstSeen[Package.id(k, t)] = .now.addingTimeInterval(-days * 86_400)
        }

        var sizes: [String: Int64] = [:]
        for i in installed { sizes[i.id] = Int64(abs(i.token.hashValue % 300) + 3) * 1_000_000 }
        sizes[Package.id(.formula, "ffmpeg")] = 54_100_000

        let root = URL(fileURLWithPath: "/opt/homebrew")
        let env = BrewEnvironment(brew: root.appending(path: "bin/brew"), prefix: root, cellar: root.appending(path: "Cellar"),
                                  // Never the real cache: demo actions must not touch real files.
                                  caskroom: root.appending(path: "Caskroom"), cache: Paths.caches.appending(path: "demo-homebrew-cache"),
                                  repository: root, version: "7.0.11 (demo)")
        return Bundle(
            catalog: Catalog(packages: packages, formulaAliases: ["rg": "ripgrep"], generatedAt: .now.addingTimeInterval(-240), sourceDescription: "demo"),
            installed: installed, outdated: outdated, popularity: pop, sizes: sizes, firstSeen: firstSeen,
            services: [BrewService(name: "postgresql@17", status: "started", user: NSUserName(), file: "~/Library/LaunchAgents/homebrew.mxcl.postgresql@17.plist", pid: 812, exitCode: 0),
                       BrewService(name: "redis", status: "stopped", user: nil, file: nil, pid: nil, exitCode: nil),
                       BrewService(name: "dnsmasq", status: "error", user: "root", file: "/Library/LaunchDaemons/homebrew.mxcl.dnsmasq.plist", pid: nil, exitCode: 78)],
            taps: [BrewTap(name: "homebrew/core", remote: "https://github.com/Homebrew/homebrew-core", path: nil, isOfficial: true, formulaCount: 8663, caskCount: 0),
                   BrewTap(name: "homebrew/cask", remote: "https://github.com/Homebrew/homebrew-cask", path: nil, isOfficial: true, formulaCount: 0, caskCount: 7799),
                   BrewTap(name: "hashicorp/tap", remote: "https://github.com/hashicorp/homebrew-tap", path: nil, isOfficial: false, formulaCount: 14, caskCount: 3),
                   BrewTap(name: "oven-sh/bun", remote: "https://github.com/oven-sh/homebrew-bun", path: nil, isOfficial: false, formulaCount: 2, caskCount: 0, trusted: false)],
            env: env)
    }
}
