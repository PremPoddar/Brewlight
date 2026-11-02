import XCTest
@testable import Brewlight

/// Budgets from the spec, measured against this Mac's real Homebrew cache when present.
final class PerformanceTests: XCTestCase {
    private func realCatalog() throws -> Catalog {
        let cache = URL.cachesDirectory.appending(path: "Homebrew")
        guard let file = CatalogLoader.internalPackagesFile(cache: cache) else {
            throw XCTSkip("No Homebrew API cache on this machine")
        }
        return try CatalogLoader.loadInternal(from: file)
    }

    /// Real install counts when reachable; ranking needs them ("chrome" → google-chrome).
    private func popularity(_ catalog: Catalog) async -> [Int] {
        let pop = await PopularityStore().refresh() ?? Popularity()
        return catalog.packages.map { pop.installs30[$0.id] ?? 0 }
    }

    func testSearchPerKeystrokeUnderOneFrame() async throws {
        let catalog = try realCatalog()
        let index = SearchIndex(packages: catalog.packages)
        let pop = await popularity(catalog)
        XCTAssertGreaterThan(index.count, 10_000)
        // Each "keystroke" of typing "ripgrep" must finish within one frame (16 ms) in an optimized
        // build — the budget the shipped app is held to. Debug builds are unoptimized and only get a
        // sanity bound; run `xcodebuild test -configuration Release ENABLE_TESTABILITY=YES` for the real check.
        #if DEBUG
        let budget = 250.0 // unoptimized, and tolerant of a busy machine
        #else
        let budget = 16.0
        #endif
        for prefix in ["r", "ri", "rip", "ripg", "ripgr", "ripgre", "ripgrep"] {
            let start = ContinuousClock.now
            _ = index.search(prefix, popularity: pop)
            let ms = (ContinuousClock.now - start).milliseconds
            XCTAssertLessThan(ms, budget, "search(\(prefix)) took \(ms) ms")
        }
        measure { _ = index.search("chrome", popularity: pop) }
    }

    func testRealSearchRanking() async throws {
        let catalog = try realCatalog()
        let index = SearchIndex(packages: catalog.packages)
        let pop = await popularity(catalog)
        XCTAssertEqual(catalog.packages[index.search("chrome", popularity: pop)[0].index].token, "google-chrome")
        XCTAssertEqual(catalog.packages[index.search("rg", popularity: pop)[0].index].token, "ripgrep")
    }

    func testSnapshotLoadIsFast() throws {
        let catalog = try realCatalog()
        let dir = FileManager.default.temporaryDirectory.appending(path: "bl-perf-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SnapshotStore(directory: dir)
        store.save(catalog, meta: .init(sourcePath: "x", sourceModified: .now, savedAt: .now))
        measure { _ = store.loadCatalog() }
    }

    func testCatalogParse() throws {
        _ = try realCatalog()
        measure { _ = try? realCatalog() }
    }
}

final class AdoptionScanRealTests: XCTestCase {
    /// Runs the real scan against this Mac's Applications folder and Homebrew catalog.
    func testRealScan() throws {
        let cache = URL.cachesDirectory.appending(path: "Homebrew")
        guard let file = CatalogLoader.internalPackagesFile(cache: cache) else { throw XCTSkip("No Homebrew API cache") }
        let catalog = try CatalogLoader.loadInternal(from: file)
        let caskroom = URL(fileURLWithPath: "/opt/homebrew/Caskroom")
        let installed = Set((try? FileManager.default.contentsOfDirectory(atPath: caskroom.path)) ?? [])
        let start = ContinuousClock.now
        let bundles = AdoptionScanner.scanBundles()
        let found = AdoptionScanner.match(bundles: bundles, casks: catalog.packages, installedCasks: installed, managedPaths: [])
        let ms = (ContinuousClock.now - start).milliseconds
        print("ADOPTSCAN \(bundles.count) apps scanned in \(Int(ms)) ms; adoptable:")
        for a in found { print("ADOPTSCAN  \(a.name) → \(a.token)  yours \(a.appVersion ?? "?") / cask \(a.caskVersion)  \(a.status)") }
        XCTAssertLessThan(ms, 2000)
    }
}

final class SmartSearchRealTests: XCTestCase {
    /// Prints how real requests are interpreted and what they find in this Mac's catalog.
    func testRealRequests() async throws {
        let cache = URL.cachesDirectory.appending(path: "Homebrew")
        guard let file = CatalogLoader.internalPackagesFile(cache: cache) else { throw XCTSkip("No Homebrew API cache") }
        let catalog = try CatalogLoader.loadInternal(from: file)
        let index = SearchIndex(packages: catalog.packages)
        let pop = (await PopularityStore().refresh() ?? Popularity())
        let byIndex = catalog.packages.map { pop.installs30[$0.id] ?? 0 }
        print("SMART model available: \(SmartSearch.isModelAvailable)")
        for request in ["an app to edit videos", "command line tool to search json files", "a tool to compress images",
                        "lightweight terminal app with tabs", "something to download youtube videos"] {
            let start = ContinuousClock.now
            let q = await SmartSearch.interpret(request)
            let ms = Int((ContinuousClock.now - start).milliseconds)
            let cats = Set(q.categories)
            let store = CategoryStore()
            let hits = index.searchWords(q.keywords.joined(separator: " "), limit: 400, popularity: byIndex)
                .map { catalog.packages[$0.index] }
                .filter { q.kind == nil || $0.kind == q.kind }
                .filter { cats.isEmpty || cats.contains(store.category(for: $0).category) }
                .prefix(5).map(\.token)
            print("SMART \"\(request)\" → \(q.queryString)  [\(q.source), \(ms) ms]  top: \(hits.joined(separator: ", "))")
        }
    }
}

final class PackageCacheRealTests: XCTestCase {
    func testRealCache() throws {
        let cache = URL.cachesDirectory.appending(path: "Homebrew")
        guard FileManager.default.fileExists(atPath: cache.path) else { throw XCTSkip("No Homebrew cache") }
        for (t, k) in [("brotli", PackageKind.formula), ("python@3.15", .formula), ("balenaetcher", .cask), ("visual-studio-code", .cask)] {
            let p = Package(kind: k, token: t, fullName: t, displayName: t, desc: "", homepage: "", version: "", tap: "")
            let e = PackageCache.entries(for: p, cache: cache)
            print("CACHE \(t): \(e.count) files, \(PackageCache.totalSize(e).byteString) — \(e.compactMap { $0.file?.lastPathComponent }.joined(separator: ", "))")
        }
    }
}
