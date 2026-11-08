import Foundation
import Testing
@testable import Brewlight

// MARK: Versions

@Suite struct VersionTests {
    @Test(arguments: [
        ("1.2.3", "1.2.4"), ("1.2.9", "1.2.10"), ("1.0beta2", "1.0"), ("1.0rc1", "1.0.1"),
        ("8.0", "8.0.1"), ("2026.7.22_1", "2026.10.23"), ("1.2.3", "1.2.3_1"),
        ("1.2.3,20260927200815", "1.2.8,20261029214736"), ("2026-09-25", "2026-10-20"),
        ("24.9.0", "24.11.0"), ("3.13.7", "3.13.9")
    ])
    func ordering(_ pair: (String, String)) {
        #expect(BrewVersion(pair.0) < BrewVersion(pair.1))
        #expect(!(BrewVersion(pair.1) < BrewVersion(pair.0)))
    }

    @Test func revisionParsing() {
        let v = BrewVersion("2.51.1_2")
        #expect(v.revision == 2)
        #expect(BrewVersion("1.0") == BrewVersion("1.0.0") || BrewVersion("1.0") < BrewVersion("1.0.0"))
        #expect(BrewVersion("latest").isUnversioned)
    }
}

// MARK: Catalog parsing

@Suite struct CatalogLoaderTests {
    static let internalPayload = """
    {"metadata":{"generated_at":1792518878},
     "formulae":{
       "ripgrep":{"aliases":["rg"],"desc":"Search tool like grep and The Silver Searcher","homepage":"https://github.com/BurntSushi/ripgrep","license":"Unlicense","stable_version":"15.2.0","stable_dependencies":["pcre2",{"rust":":build"},{"pkgconf":[":build",":test"]}],"bottle_checksum":"abc","unknown_future_field":{"x":1}},
       "ffmpeg":{"desc":"Play, record, convert, and stream","homepage":"https://ffmpeg.org/","license":"GPL-3.0-or-later","stable_version":"9.0.2","revision":1,"caveats":"Use ffmpeg-full for extras.\\n","stable_dependencies":["dav1d","lame",{"pkgconf":":build"}],"stable_uses_from_macos":[["bzip2"],["libxml2"]],"versioned_formulae":["ffmpeg@8"]},
       "oldthing":{"desc":"Old","homepage":"https://example.com","stable_version":"1","deprecate_args":{":because":":unmaintained",":replacement_formula":"newthing"}},
       "pcre2":{"desc":"Perl regex","homepage":"https://pcre.org","stable_version":"10"},
       "dav1d":{"desc":"AV1","homepage":"https://x","stable_version":"1"},
       "lame":{"desc":"MP3","homepage":"https://x","stable_version":"3"}
     },
     "casks":{
       "google-chrome":{"names":["Google Chrome"],"desc":"Web browser","homepage":"https://www.google.com/chrome/","version":"155.0","tap_string":"homebrew/cask","auto_updates":true,
         "depends_on_args":{":macos":":ventura"},
         "raw_artifacts":[[":app",["Google Chrome.app"]],[":zap",{":trash":["~/Library/Caches/Google/Chrome","~/Library/Preferences/com.google.Chrome.plist"],":rmdir":["~/Library/Google"]}]]}
     },
     "formula_aliases":{"rg":"ripgrep","ffmpeg@9":"ffmpeg"},
     "formula_renames":{"oldrg":"ripgrep"},
     "cask_renames":{"chrome":"google-chrome"}}
    """

    @Test func parsesInternalFormat() throws {
        let catalog = try CatalogLoader.parseInternal(Data(Self.internalPayload.utf8), source: "test")
        #expect(catalog.packages.count == 7)
        let rg = try #require(catalog.packages.first { $0.token == "ripgrep" })
        #expect(rg.kind == .formula)
        #expect(rg.dependencies == ["pcre2"])
        #expect(Set(rg.buildDependencies) == ["rust", "pkgconf"])
        #expect(rg.aliases.contains("rg"))
        #expect(rg.oldNames.contains("oldrg"))
        #expect(rg.hasBottle)

        let ff = try #require(catalog.packages.first { $0.token == "ffmpeg" })
        #expect(ff.fullVersion == "9.0.2_1")
        #expect(ff.usesFromMacOS == ["bzip2", "libxml2"])
        #expect(ff.caveats?.contains("ffmpeg-full") == true)

        let old = try #require(catalog.packages.first { $0.token == "oldthing" })
        #expect(old.isDeprecated)
        #expect(old.replacement == "newthing")

        let chrome = try #require(catalog.packages.first { $0.token == "google-chrome" })
        #expect(chrome.kind == .cask)
        #expect(chrome.displayName == "Google Chrome")
        #expect(chrome.appNames == ["Google Chrome.app"])
        #expect(chrome.zapPaths.count == 3)
        #expect(chrome.autoUpdates)
        #expect(chrome.macOSRequirement == "ventura")
        #expect(chrome.oldNames == ["chrome"])
    }

    @Test func unwrapsJWS() throws {
        let inner = #"{"formulae":{},"casks":{}}"#
        let jws = try JSONSerialization.data(withJSONObject: ["payload": inner, "signatures": []])
        let unwrapped = try CatalogLoader.unwrapJWS(jws)
        #expect(String(decoding: unwrapped, as: UTF8.self) == inner)
        // Plain JSON passes through untouched.
        #expect(try CatalogLoader.unwrapJWS(Data(inner.utf8)) == Data(inner.utf8))
    }

    @Test func parsesLegacyFormat() throws {
        let formulae = """
        [{"name":"jq","full_name":"jq","tap":"homebrew/core","aliases":[],"oldnames":[],"desc":"JSON processor","homepage":"https://jqlang.github.io/jq/","license":"MIT","versions":{"stable":"1.8.1","head":"HEAD"},"revision":0,"bottle":{"stable":{}},"dependencies":["oniguruma"],"build_dependencies":["autoconf"],"deprecated":false,"disabled":false}]
        """
        let casks = """
        [{"token":"iterm2","full_token":"iterm2","tap":"homebrew/cask","name":["iTerm2"],"desc":"Terminal emulator","homepage":"https://iterm2.com/","version":"3.6.5","auto_updates":true,"artifacts":[{"app":["iTerm.app"]},{"zap":[{"trash":["~/Library/Preferences/com.googlecode.iterm2.plist"]}]}],"depends_on":{"macos":{">=":["10.15"]}}}]
        """
        let c = try CatalogLoader.parseLegacy(formulae: Data(formulae.utf8), casks: Data(casks.utf8), source: "test")
        let jq = try #require(c.packages.first { $0.token == "jq" })
        #expect(jq.dependencies == ["oniguruma"])
        #expect(jq.hasHead)
        let iterm = try #require(c.packages.first { $0.token == "iterm2" })
        #expect(iterm.appNames == ["iTerm.app"])
        #expect(iterm.zapPaths.count == 1)
        #expect(iterm.macOSRequirement == ">= 10.15")
    }
}

// MARK: Receipts

@Suite struct ReceiptTests {
    @Test func formulaReceipt() throws {
        let json = """
        {"installed_on_request":false,"installed_as_dependency":true,"poured_from_bottle":true,"time":1787419274,
         "runtime_dependencies":[{"full_name":"pcre2","version":"10.45"},{"full_name":"user/tap/thing"}],
         "source":{"tap":"homebrew/core"},"changed_files":["a","b"]}
        """
        let r = try #require(Receipt.parse(Data(json.utf8)))
        #expect(r.installedOnRequest == false)
        #expect(r.installedAsDependency == true)
        #expect(r.runtimeDependencies == ["pcre2", "user/tap/thing"])
        #expect(r.tap == "homebrew/core")
        #expect(r.time == Date(timeIntervalSince1970: 1_787_419_274))
    }

    @Test func caskReceipt() throws {
        let json = #"{"installed_on_request":true,"time":1774301919,"source":{"tap":"homebrew/cask"},"uninstall_artifacts":[{"app":["Ghostty.app"]},{"manpage":["x"]}]}"#
        let r = try #require(Receipt.parse(Data(json.utf8)))
        #expect(r.appNames == ["Ghostty.app"])
    }

    @Test func toleratesGarbage() {
        #expect(Receipt.parse(Data("not json".utf8)) == nil)
    }
}

// MARK: Search

@Suite struct SearchTests {
    static let packages: [Package] = {
        func p(_ t: String, _ k: PackageKind = .formula, desc: String = "", aliases: [String] = [], home: String = "") -> Package {
            var x = Package(kind: k, token: t, fullName: t, displayName: t, desc: desc, homepage: home, version: "1", tap: "homebrew/core")
            x.aliases = aliases
            return x
        }
        return [
            p("google-chrome", .cask, desc: "Web browser", home: "https://www.google.com/chrome/"),
            p("chromedriver", .cask, desc: "Automated testing of webapps for Google Chrome"),
            p("chromium", .cask, desc: "Free and open-source web browser"),
            p("ripgrep", desc: "Search tool like grep and The Silver Searcher", aliases: ["rg"]),
            p("ripgrep-all", desc: "ripgrep, but also PDFs"),
            p("rgbds", desc: "Rednex GameBoy Development System"),
            p("grep", desc: "GNU grep, egrep and fgrep"),
            p("jq", desc: "Lightweight and flexible command-line JSON processor")
        ]
    }()

    @Test func chromeFindsGoogleChromeFirst() {
        let idx = SearchIndex(packages: Self.packages)
        let pop: [String: Int] = ["google-chrome": 180_000, "chromium": 5_000, "chromedriver": 3_000]
        let hits = idx.search("chrome", popularity: Self.packages.map { pop[$0.token] ?? 0 })
        #expect(Self.packages[hits[0].index].token == "google-chrome")
    }

    @Test func rgFindsRipgrepViaAlias() {
        let idx = SearchIndex(packages: Self.packages)
        let hits = idx.search("rg")
        #expect(Self.packages[hits[0].index].token == "ripgrep")
    }

    @Test func exactNameWins() {
        let idx = SearchIndex(packages: Self.packages)
        #expect(Self.packages[idx.search("grep")[0].index].token == "grep")
        #expect(Self.packages[idx.search("ripgrep")[0].index].token == "ripgrep")
    }

    @Test func descriptionWordMatch() {
        let idx = SearchIndex(packages: Self.packages)
        #expect(idx.search("json").contains { Self.packages[$0.index].token == "jq" })
    }

    @Test func queryFilters() {
        let q = SearchQuery("chrome is:installed type:cask tag:Work tap:homebrew/cask cat:browsers")
        #expect(q.text == "chrome")
        #expect(q.isInstalled)
        #expect(q.kind == .cask)
        #expect(q.tags == ["Work"])
        #expect(q.taps == ["homebrew/cask"])
        #expect(q.categories == ["browsers"])
    }
}

// MARK: Dependency graph

@Suite struct GraphTests {
    static func pkg(_ t: String, _ deps: [String] = [], build: [String] = []) -> Package {
        var p = Package(kind: .formula, token: t, fullName: t, displayName: t, desc: "", homepage: "", version: "1", tap: "homebrew/core")
        p.dependencies = deps
        p.buildDependencies = build
        return p
    }

    // ffmpeg -> x264, lame, openssl -> ca-certs; yt-dlp -> ffmpeg, python -> openssl
    static let graph = DependencyGraph(packages: [
        pkg("ffmpeg", ["x264", "lame", "openssl"], build: ["pkgconf"]), pkg("x264"), pkg("lame"),
        pkg("openssl", ["ca-certs"]), pkg("ca-certs"), pkg("yt-dlp", ["ffmpeg", "python"]), pkg("python", ["openssl"]),
        pkg("cyclic-a", ["cyclic-b"]), pkg("cyclic-b", ["cyclic-a"]), pkg("pkgconf")
    ])

    @Test func transitive() {
        let deps = Self.graph.transitiveDependencies(of: "yt-dlp")
        #expect(Set(deps) == ["ffmpeg", "python", "x264", "lame", "openssl", "ca-certs"])
        #expect(Self.graph.transitiveDependencies(of: "ffmpeg", includeBuild: true).contains("pkgconf"))
    }

    @Test func cyclesTerminate() {
        #expect(Self.graph.transitiveDependencies(of: "cyclic-a") == ["cyclic-b"])
        #expect(!Self.graph.tree(of: "cyclic-a", includeBuild: false).isEmpty)
    }

    @Test func reverseAndLeaves() {
        let installed: Set<String> = ["ffmpeg", "x264", "lame", "openssl", "ca-certs", "yt-dlp", "python"]
        #expect(Self.graph.dependents(of: "openssl", installed: installed) == ["ffmpeg", "python"])
        #expect(Self.graph.leaves(installed: installed) == ["yt-dlp"])
    }

    @Test func orphansAndWhy() {
        let installed: Set<String> = ["ffmpeg", "x264", "lame", "openssl", "ca-certs", "python"]
        // Only python requested: ffmpeg & friends are orphans.
        #expect(Self.graph.orphans(installed: installed, requested: ["python"]) == ["ffmpeg", "lame", "x264"])
        let why = Self.graph.whyInstalled("ca-certs", installed: installed.union(["yt-dlp"]), requested: ["yt-dlp"])
        #expect(why.contains { $0.first == "yt-dlp" && $0.last == "ca-certs" })
    }

    @Test func ffmpegTreeIsFast() {
        // 60-node chain stays well inside the 100 ms budget.
        var pkgs = (0..<60).map { Self.pkg("lib\($0)", $0 < 59 ? ["lib\($0 + 1)"] : []) }
        pkgs.append(Self.pkg("big", (0..<60).map { "lib\($0)" }))
        let g = DependencyGraph(packages: pkgs)
        let start = ContinuousClock.now
        _ = g.tree(of: "big", includeBuild: true)
        #expect((ContinuousClock.now - start) < .milliseconds(100))
    }
}

// MARK: Categories

@Suite struct CategoryTests {
    func p(_ t: String, _ k: PackageKind = .formula, _ desc: String) -> Package {
        Package(kind: k, token: t, fullName: t, displayName: t, desc: desc, homepage: "", version: "1", tap: "homebrew/core")
    }

    @Test func heuristics() {
        #expect(CategoryStore.heuristic(p("font-fira-code", .cask, "Typeface")) == .fonts)
        #expect(CategoryStore.heuristic(p("pgcli", .formula, "CLI for Postgres database")) == .databases)
        #expect(CategoryStore.heuristic(p("ffmpeg", .formula, "Play, record, convert, and stream audio and video")) == .media)
        #expect(CategoryStore.heuristic(p("zzz", .formula, "")) == .other)
    }

    @Test func bundledBeatsHeuristicAndOverrideBeatsBundled() {
        let store = CategoryStore(json: Data(#"{"version":2,"categories":{"Browsers":["cask:firefox"],"Developer Tools":["jq"]}}"#.utf8))
        let ff = p("firefox", .cask, "something about video")
        #expect(store.category(for: ff) == .init(category: .browsers, isAuto: false))
        #expect(store.category(for: p("jq", .formula, "")) == .init(category: .developerTools, isAuto: false))
        #expect(store.category(for: ff, overrides: [ff.id: "Games"]).category == .games)
        #expect(store.category(for: p("x", .formula, "")).isAuto)
    }

    @Test func bundledFileLoads() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "categories", withExtension: "json")
            ?? Bundle.main.url(forResource: "categories", withExtension: "json"))
        let store = CategoryStore(json: try Data(contentsOf: url))
        #expect(store.version >= 1)
    }
}

final class BundleToken {}

// MARK: Brewfile

@Suite struct BrewfileTests {
    static let text = """
    # Taps
    tap "homebrew/bundle"
    tap "hashicorp/tap"
    # Lightweight and flexible command-line JSON processor
    brew "jq"
    brew "hashicorp/tap/terraform"
    brew "git", link: true
    cask "iterm2"
    cask "zed"
    mas "Xcode", id: 497799835
    vscode "ms-python.python"
    """

    @Test func parse() {
        let b = Brewfile.parse(Self.text)
        #expect(b.entries.count == 9)
        #expect(b.entries.filter { $0.section == .brew }.map(\.name) == ["jq", "hashicorp/tap/terraform", "git"])
        #expect(b.entries.first { $0.section == .mas }?.name == "Xcode")
    }

    @Test func diff() {
        let d = Brewfile.parse(Self.text).diff(installedFormulae: ["jq", "git", "wget"], installedCasks: ["iterm2", "slack"],
                                               taps: ["homebrew/bundle"], requestedFormulae: ["jq", "wget"])
        #expect(Set(d.toInstall.map(\.name)) == ["hashicorp/tap", "hashicorp/tap/terraform", "zed", "Xcode", "ms-python.python"])
        #expect(Set(d.alreadyPresent.map(\.name)) == ["homebrew/bundle", "jq", "git", "iterm2"])
        #expect(d.extra == ["wget", "cask: slack"])
    }

    @Test func filterSections() {
        let out = Brewfile.filter(Self.text, keep: [.brew])
        #expect(out.contains("brew \"jq\""))
        #expect(out.contains("# Lightweight"))
        #expect(!out.contains("cask "))
        #expect(!out.contains("tap "))
    }
}

// MARK: Snapshot diff (new packages)

@Suite struct SnapshotTests {
    @Test func firstRunSeedsOnlyKnownNew() {
        let now = Date()
        let result = SnapshotStore.diff(previous: [:], currentIDs: ["formula:a", "formula:b", "cask:c"], now: now, seedNew: ["cask:c"])
        #expect(result["formula:a"] == .distantPast)
        #expect(result["cask:c"] == now)
    }

    @Test func laterRunsMarkAdditions() {
        let t0 = Date(timeIntervalSince1970: 0)
        let now = Date()
        let result = SnapshotStore.diff(previous: ["formula:a": t0], currentIDs: ["formula:a", "formula:new"], now: now, seedNew: [])
        #expect(result["formula:a"] == t0)
        #expect(result["formula:new"] == now)
    }

    @Test func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bl-snap-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SnapshotStore(directory: dir)
        let catalog = try CatalogLoader.parseInternal(Data(CatalogLoaderTests.internalPayload.utf8), source: "t")
        store.save(catalog, meta: .init(sourcePath: "x", sourceModified: .distantPast, savedAt: .now))
        let loaded = try #require(store.loadCatalog())
        #expect(loaded.0.packages == catalog.packages)
    }
}

// MARK: Output parsing

@Suite struct ParserTests {
    @Test func progress() {
        #expect(ProgressParser.parse("==> Downloading https://ghcr.io/v2/x").phase == .downloading)
        #expect(ProgressParser.parse("==> Pouring ffmpeg--8.0.1.arm64_tahoe.bottle.tar.gz").phase == .pouring)
        #expect(ProgressParser.parse("######################################   64.0%").percent == 0.64)
        #expect(ProgressParser.parse("==> Linking ffmpeg").phase == .linking)
        #expect(ProgressParser.parse("Error: No such keg").isError)
        #expect(ProgressParser.parse("sudo: a terminal is required to read the password").needsTerminal)
        #expect(ProgressParser.parse("Uninstalling /opt/homebrew/Cellar/jq/1.8.1... (20 files)").phase == .uninstalling)
    }

    @Test func doctorWarnings() {
        let out = """
        Please note that these warnings are just used to help the Homebrew maintainers
        Warning: Some installed formulae are deprecated or disabled.
        You should find replacements for the following formulae:
          oldthing

        Warning: You have unlinked kegs in your Cellar.
          node@20
        """
        let w = MaintenanceParsers.doctor(out)
        #expect(w.count == 2)
        #expect(w[0].title.hasPrefix("Some installed formulae"))
        #expect(w[1].body.contains("node@20"))
    }

    @Test func cleanupPreview() {
        let out = """
        Would remove: /opt/homebrew/var/homebrew/tmp/.caskroom/discord (290 files, 504MB)
        Would remove: /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.7_1 (1,707 files, 34.6MB)
        ==> This operation would free approximately 2.4GB of disk space.
        """
        let c = MaintenanceParsers.cleanup(out)
        #expect(c.items.count == 2)
        #expect(c.reclaimable == "2.4GB")
    }

    @Test func autoremovePreview() {
        let out = "==> Would autoremove 3 unneeded formulae:\nlibfoo\nlibbar\nlibbaz\n"
        #expect(MaintenanceParsers.autoremove(out) == ["libfoo", "libbar", "libbaz"])
    }

    @Test func analytics() {
        let json = #"{"items":[{"number":1,"formula":"ca-certificates","count":"506,988"},{"number":2,"formula":"ffmpeg --HEAD","count":"12"},{"number":3,"formula":"ffmpeg","count":"1,000"}]}"#
        let p = PopularityStore.parse(Data(json.utf8))
        #expect(p["formula:ca-certificates"] == 506_988)
        #expect(p["formula:ffmpeg"] == 1_012)
    }

    @Test func services() {
        let json: Any = [["name": "postgresql@17", "status": "started", "user": "me", "pid": 812], ["name": "redis", "status": "none"]]
        let s = BrewService.parse(json)
        #expect(s[0].isRunning && s[0].pid == 812)
        #expect(!s[1].isRunning)
    }

    @Test func tapNames() {
        #expect(BrewTap.isValidName("hashicorp/tap"))
        #expect(BrewTap.isValidName("https://example.com/x.git"))
        #expect(!BrewTap.isValidName("nope"))
        #expect(!BrewTap.isValidName("a/b/c"))
    }
}

// MARK: Mock runner

@Suite struct RunnerTests {
    @Test func mockReplaysOutput() async {
        let runner = MockBrewRunner(responses: ["outdated --json=v2": (lines: [#"{"formulae":[],"casks":[]}"#], status: 0)], lineDelay: .zero)
        let r = await runner.output(["outdated", "--json=v2"])
        #expect(r.status == 0)
        #expect(r.stdout.contains("formulae"))
    }

    @MainActor @Test func operationCenterSerializesAndParsesProgress() async throws {
        let center = OperationCenter()
        center.configure(runner: MockBrewRunner(lineDelay: .milliseconds(1)))
        let a = center.enqueue("Install a", ["install", "a"], packages: ["a"])
        let b = center.enqueue("Install b", ["install", "b"], packages: ["b"])
        #expect(b.state == .queued)
        while center.hasActive { try await Task.sleep(for: .milliseconds(10)) }
        #expect(a.state == .succeeded && b.state == .succeeded)
        #expect(a.finishedAt! <= b.startedAt!)
        #expect(a.log.contains { $0.text.contains("Pouring") })
    }
}

// MARK: Formatting

@Suite struct FormattingTests {
    @Test(arguments: [(0, "0"), (999, "999"), (1_000, "1K"), (48_210, "48.2K"), (161_000, "161K"),
                      (999_499, "999K"), (999_500, "1M"), (4_108_770, "4.1M"), (25_084_336, "25.1M")])
    func compactCounts(_ pair: (Int, String)) {
        #expect(pair.0.compact == pair.1)
    }
}

// MARK: Activity log

@Suite struct LogTests {
    static let tapTrustOutput = """
    Warning: The following taps are not trusted:
      sinelaw/fresh
    Homebrew is currently ignoring formulae, casks and commands
    from these taps because tap trust is required.
    Untap them with:
      brew untap sinelaw/fresh
    Trust whole taps with:
      brew trust sinelaw/fresh
    For more information, see:
      https://docs.brew.sh/Tap-Trust
    ==> Fetching downloads for: 0-ad
    ######################################################################## 100.0%
    ==> Pouring 0-ad--0.27.1.arm64_tahoe.bottle.tar.gz
    🍺  /opt/homebrew/Cellar/0-ad/0.27.1: 1,234 files, 1.2GB
    Error: Something broke
      at line 3
    """

    @Test func classifiesBlocks() {
        var c = LogClassifier()
        let kinds = Self.tapTrustOutput.split(separator: "\n", omittingEmptySubsequences: false).map { c.classify(String($0)) }
        #expect(kinds[0] == .warning)
        #expect(kinds[1...9].allSatisfy { $0 == .warning })   // the whole warning block
        #expect(kinds[10] == .heading)
        #expect(kinds[11] == .progress)
        #expect(kinds[12] == .heading)
        #expect(kinds[13] == .success)
        #expect(kinds[14] == .error)
        #expect(kinds[15] == .error)                           // continuation of the error
    }

    @Test func detectsUntrustedTaps() {
        var d = NoticeDetector()
        var notices: [OperationNotice] = []
        for line in Self.tapTrustOutput.split(separator: "\n") {
            if let n = d.feed(String(line)) { notices.append(n) }
        }
        if let n = d.flush() { notices.append(n) }
        #expect(notices == [.untrustedTaps(["sinelaw/fresh"])])
    }

    @Test func detectsSeveralTapsAtEndOfOutput() {
        var d = NoticeDetector()
        for line in ["Warning: The following taps are not trusted:", "  anomalyco/tap", "  sinelaw/fresh"] { _ = d.feed(line) }
        #expect(d.flush() == .untrustedTaps(["anomalyco/tap", "sinelaw/fresh"]))
    }

    @Test func parsesTapTrust() {
        let json: Any = [["name": "sinelaw/fresh", "official": false, "trusted": false], ["name": "homebrew/core", "official": true, "trusted": true]]
        let taps = BrewTap.parse(json)
        #expect(taps[0].trusted == false)
        #expect(taps[1].trusted == true)
    }
}

// MARK: Doctor suggestions

@Suite struct DoctorSuggestionTests {
    @Test func suggestionsFromRealWarnings() throws {
        let warnings = MaintenanceParsers.doctor(MockBrewRunner.demoDoctor)
        #expect(warnings.count == 3)

        let deprecated = MaintenanceParsers.suggestions(for: warnings[0])
        #expect(deprecated == [.package("icu4c@78")])

        let certs = MaintenanceParsers.suggestions(for: warnings[1])
        // CA names have spaces, so they aren't mistaken for packages.
        #expect(certs.count == 2)
        guard case .terminal(let cmd) = certs[0] else { Issue.record("expected a terminal command"); return }
        #expect(cmd.hasPrefix("sudo /opt/homebrew/Library/Homebrew/vendor/portable-ruby"))
        #expect(certs[1] == .link(URL(string: "https://support.apple.com/en-us/149555")!))

        #expect(MaintenanceParsers.suggestions(for: warnings[2]) == [.package("node")])
    }

    @Test func brewCommandsAndPlaceholders() {
        let w = MaintenanceParsers.DoctorWarning(title: "x", body: """
          brew untap sinelaw/fresh
          brew trust --formula <user>/<tap>/<formula>
        """)
        // Placeholder commands are skipped; real ones become runnable.
        #expect(MaintenanceParsers.suggestions(for: w) == [.brew(["untap", "sinelaw/fresh"])])
    }
}

// MARK: Adoption

@Suite struct AdoptionTests {
    func cask(_ token: String, app: String, version: String) -> Package {
        var p = Package(kind: .cask, token: token, fullName: token, displayName: token, desc: "", homepage: "", version: version, tap: "homebrew/cask")
        p.appNames = [app]
        return p
    }

    @Test func matchesByAppName() {
        let casks = [cask("firefox", app: "Firefox.app", version: "140.0"), cask("firefox@beta", app: "Firefox.app", version: "141.0b1"),
                     cask("zed", app: "Zed.app", version: "0.208.4,abc"), cask("iterm2", app: "iTerm.app", version: "3.6.5"),
                     cask("things", app: "Things3.app", version: "3.22")]
        let bundles: [AdoptionScanner.AppBundle] = [
            .init(path: "/Applications/Firefox.app", fileName: "Firefox.app", version: "140.0", bundleID: "org.mozilla.firefox", isAppStore: false),
            .init(path: "/Applications/Zed.app", fileName: "Zed.app", version: "0.206.1", bundleID: "dev.zed.Zed", isAppStore: false),
            .init(path: "/Applications/iTerm.app", fileName: "iTerm.app", version: "3.6.5", bundleID: "com.googlecode.iterm2", isAppStore: false),
            .init(path: "/Applications/Things3.app", fileName: "Things3.app", version: "3.22", bundleID: "com.culturedcode.ThingsMac", isAppStore: true),
            .init(path: "/Applications/Safari.app", fileName: "Safari.app", version: "26.0", bundleID: "com.apple.Safari", isAppStore: false),
            .init(path: "/Applications/Unknown.app", fileName: "Unknown.app", version: "1", bundleID: "x.y", isAppStore: false)
        ]
        let result = AdoptionScanner.match(bundles: bundles, casks: casks, installedCasks: ["iterm2"], managedPaths: [])
        #expect(result.map(\.token) == ["firefox", "things", "zed"])      // iTerm already a cask, Apple/unknown skipped
        #expect(result[0].status == .ready)                                 // main cask preferred over @beta
        #expect(result[1].status == .appStore)
        #expect(result[2].status == .versionDiffers)
    }

    @Test func caskBuildSuffixIgnored() {
        let a = AdoptableApp(path: "/a", name: "A", token: "a", appVersion: "1.2.3", caskVersion: "1.2.3,20260101", bundleID: nil, isAppStore: false)
        #expect(a.versionMatches)
    }

    @Test func oneRowPerCask() {
        let c = cask("openra", app: "OpenRA - Red Alert.app", version: "20250330")
        var multi = c
        multi.appNames = ["OpenRA - Red Alert.app", "OpenRA - Dune 2000.app"]
        let bundles: [AdoptionScanner.AppBundle] = ["OpenRA - Red Alert.app", "OpenRA - Dune 2000.app"].map {
            .init(path: "/Applications/" + $0, fileName: $0, version: "release-20250330", bundleID: "net.openra.\($0.count)", isAppStore: false)
        }
        let r = AdoptionScanner.match(bundles: bundles, casks: [multi], installedCasks: [], managedPaths: [])
        #expect(r.count == 1)
        #expect(r[0].name.contains("Dune 2000") && r[0].name.contains("Red Alert"))
    }

    @Test func managedPathsSkipped() {
        let casks = [cask("zed", app: "Zed.app", version: "1")]
        let b = AdoptionScanner.AppBundle(path: "/Applications/Zed.app", fileName: "Zed.app", version: "1", bundleID: "dev.zed.Zed", isAppStore: false)
        #expect(AdoptionScanner.match(bundles: [b], casks: casks, installedCasks: [], managedPaths: ["/Applications/Zed.app"]).isEmpty)
    }
}

// MARK: Network

@Suite struct NetworkTests {
    @Test func proxyFromSystemSettings() {
        let env = NetworkSettings.proxyEnvironment(from: [
            "HTTPEnable": 1, "HTTPProxy": "proxy.local", "HTTPPort": 3128,
            "HTTPSEnable": 1, "HTTPSProxy": "proxy.local", "HTTPSPort": 3129,
            "SOCKSEnable": 0, "ExceptionsList": ["*.local", "169.254/16"]
        ])
        #expect(env["http_proxy"] == "http://proxy.local:3128")
        #expect(env["https_proxy"] == "http://proxy.local:3129")
        #expect(env["all_proxy"] == nil)
        #expect(env["no_proxy"] == ".local,169.254/16")
    }

    @Test func mirrorSetsHomebrewVariables() {
        let d = UserDefaults(suiteName: "bl-net-\(UUID())")!
        d.set(DownloadMirror.tuna.rawValue, forKey: NetworkSettings.mirrorKey)
        d.set(false, forKey: NetworkSettings.useSystemProxyKey)
        let env = NetworkSettings.environment(defaults: d) { nil }
        #expect(env["HOMEBREW_BOTTLE_DOMAIN"] == "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles")
        #expect(env["HOMEBREW_API_DOMAIN"]?.hasSuffix("/api") == true)
        d.set(DownloadMirror.official.rawValue, forKey: NetworkSettings.mirrorKey)
        #expect(NetworkSettings.environment(defaults: d) { nil }.isEmpty)
    }
}

// MARK: Smart search

@Suite struct SmartSearchTests {
    @Test func detectsNaturalLanguage() {
        #expect(SmartSearch.looksLikeNaturalLanguage("an app to edit videos"))
        #expect(!SmartSearch.looksLikeNaturalLanguage("ripgrep"))
        #expect(!SmartSearch.looksLikeNaturalLanguage("type:cask video editor"))
    }

    @Test func keywordFallback() {
        let q = SmartSearch.heuristic("an app to edit videos")
        #expect(q.kind == .cask)
        #expect(q.categories == [.media])
        #expect(q.keywords == ["edit", "video"])
        #expect(q.queryString.hasPrefix("type:cask cat:media"))

        let cli = SmartSearch.heuristic("command line tool to search json files")
        #expect(cli.kind == .formula)
        #expect(cli.keywords == ["search", "json", "file"])
    }

    @Test func multiWordSearchPrefersPackagesMatchingMoreWords() {
        func p(_ t: String, _ d: String) -> Package {
            Package(kind: .formula, token: t, fullName: t, displayName: t, desc: d, homepage: "", version: "1", tap: "homebrew/core")
        }
        let pkgs = [p("aaa", "Video player"), p("bbb", "Video editor for creators"), p("ccc", "Text editor")]
        let idx = SearchIndex(packages: pkgs)
        let hits = idx.searchWords("video editor")
        #expect(pkgs[hits[0].index].token == "bbb")
        #expect(Set(hits.map { pkgs[$0.index].token }) == ["aaa", "bbb", "ccc"])
    }
}

// MARK: Download cache

@Suite struct PackageCacheTests {
    @Test func findsOnlyThisPackagesFiles() throws {
        let fm = FileManager.default
        let cache = fm.temporaryDirectory.appending(path: "bl-cache-\(UUID())")
        let downloads = cache.appending(path: "downloads")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache.appending(path: "Cask"), withIntermediateDirectories: true)
        func file(_ name: String, _ bytes: Int) throws -> String {
            try Data(count: bytes).write(to: downloads.appending(path: name))
            return "downloads/" + name
        }
        try fm.createSymbolicLink(atPath: cache.appending(path: "python--3.15.2").path, withDestinationPath: try file("aa--python--3.15.2.bottle.tar.gz", 5000))
        try fm.createSymbolicLink(atPath: cache.appending(path: "python_bottle_manifest--3.15.2").path, withDestinationPath: try file("bb--python-3.15.2.bottle_manifest.json", 100))
        try fm.createSymbolicLink(atPath: cache.appending(path: "python@3.14--3.14.10").path, withDestinationPath: try file("cc--python@3.14--3.14.10.bottle.tar.gz", 7000))
        try fm.createSymbolicLink(atPath: cache.appending(path: "Cask/zed--0.208.4.dmg").path, withDestinationPath: "../" + (try file("dd--Zed.dmg", 9000)))

        func pkg(_ t: String, _ k: PackageKind) -> Package {
            Package(kind: k, token: t, fullName: t, displayName: t, desc: "", homepage: "", version: "1", tap: "homebrew/core")
        }
        let py = PackageCache.entries(for: pkg("python", .formula), cache: cache)
        #expect(py.count == 2)                                  // not python@3.14's file
        #expect(py.allSatisfy { $0.file?.lastPathComponent.contains("python@") == false })
        let zed = PackageCache.entries(for: pkg("zed", .cask), cache: cache)
        #expect(zed.count == 1 && zed[0].file?.lastPathComponent == "dd--Zed.dmg")

        #expect(PackageCache.remove(py).isEmpty)
        #expect(!fm.fileExists(atPath: cache.appending(path: "python--3.15.2").path))
        #expect(fm.fileExists(atPath: downloads.appending(path: "cc--python@3.14--3.14.10.bottle.tar.gz").path))
    }

    /// A package's cached files might be real files (older Homebrew layouts), not symlinks.
    @Test func listsRealCachedFilesNotJustSymlinks() throws {
        let fm = FileManager.default
        let cache = fm.temporaryDirectory.appending(path: "bl-cache-real-\(UUID())")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cache) }

        try Data(count: 100).write(to: cache.appending(path: "fd--10.3.0.zip"))                 // real file
        try fm.createSymbolicLink(atPath: cache.appending(path: "fd_bottle_manifest--10.3.0.json").path,
                                  withDestinationPath: "fd--10.3.0.zip")                        // working link
        try fm.createSymbolicLink(atPath: cache.appending(path: "fd--9.0.1.zip").path,
                                  withDestinationPath: "gone-from-downloads")                   // broken link
        try Data(count: 400).write(to: cache.appending(path: "ripgrep--14.1.1.zip"))            // another package

        let p = Package(kind: .formula, token: "fd", fullName: "fd", displayName: "fd", desc: "", homepage: "", version: "10.3.0", tap: "homebrew/core")
        let entries = PackageCache.entries(for: p, cache: cache)

        #expect(entries.count == 3)
        // diskSize reports allocated (block-rounded) bytes, so assert the relationships:
        let real = entries.first { $0.file?.lastPathComponent == "fd--10.3.0.zip" }
        #expect((real?.size ?? 0) > 0)                       // the real file's data is counted
        let linked = entries.first { $0.link.lastPathComponent == "fd_bottle_manifest--10.3.0.json" }
        #expect(linked?.file == real?.file && linked?.size == real?.size)

        let broken = entries.first { $0.link.lastPathComponent == "fd--9.0.1.zip" }
        #expect(broken?.file == nil && broken?.size == 0)
    }

    /// `remove` must not strike a real file (link == file there) a second time and report it failed.
    @Test func removingDoesNotRevisitOneFileTwice() throws {
        let fm = FileManager.default
        let cache = fm.temporaryDirectory.appending(path: "bl-cache-rm-\(UUID())")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cache) }
        try Data(count: 10).write(to: cache.appending(path: "fd--10.3.0.zip"))

        let p = Package(kind: .formula, token: "fd", fullName: "fd", displayName: "fd", desc: "", homepage: "", version: "10.3.0", tap: "homebrew/core")
        #expect(PackageCache.remove(PackageCache.entries(for: p, cache: cache)).isEmpty)
        #expect((try? fm.contentsOfDirectory(atPath: cache.path).isEmpty) == true)
    }
}

// MARK: Brew path detection

/// Homebrew found via a path containing a space (Settings override) must still resolve.
@Suite struct BrewPathDetectionTests {
    @Test func resolveQuotesPathsContainingSpaces() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "bl-brew space-\(UUID())")
        let brew = dir.appending(path: "bin").appending(path: "brew")
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let script = """
        #!/bin/sh
        echo "\(dir.path)/prefix"
        echo "/fake/cellar"
        echo "/fake/caskroom"
        echo "/fake/cache"
        echo "/fake/repository"
        echo "Homebrew 4.4.0"
        """
        try script.write(to: brew, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)

        let env = BrewLocator.resolve(brew: brew)
        #expect(env?.brew == brew)
        #expect(env?.prefix.path == dir.appending(path: "prefix").path)
        #expect(env?.version == "4.4.0")
    }
}

// MARK: First seen

@Suite struct FirstSeenTests {
    /// Packages that leave the catalog must not keep their first-seen date forever.
    @Test func dropsRetiredPackageIDs() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let map = SnapshotStore.diff(previous: ["formula:old": .distantPast, "formula:stay": .distantPast],
                                     currentIDs: ["formula:stay", "formula:new"], now: now, seedNew: [])
        #expect(map["formula:old"] == nil)
        #expect(map["formula:stay"] == .distantPast)
        #expect(map["formula:new"] == now)
    }

    /// An empty catalog (e.g. a parse failure) must not wipe every record.
    @Test func keepsEverythingWhenCatalogIsEmpty() {
        let map = SnapshotStore.diff(previous: ["formula:stay": .distantPast],
                                     currentIDs: [], now: .now, seedNew: [])
        #expect(map["formula:stay"] == .distantPast)
    }
}
