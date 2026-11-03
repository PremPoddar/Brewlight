import Foundation
import os

/// Loads the catalog with the fastest correct source:
/// 1. our own binary snapshot (if Homebrew's cache hasn't changed since we wrote it),
/// 2. Homebrew's local API cache (no network),
/// 3. formulae.brew.sh (ETag-cached) when there is no local cache.
actor CatalogStore {
    private let snapshots: SnapshotStore
    private static let log = Logger(subsystem: "com.prempoddar.brewlight", category: "catalog")

    init(directory: URL = Paths.appSupport) {
        snapshots = SnapshotStore(directory: directory)
    }

    struct LoadResult: Sendable {
        var catalog: Catalog
        var firstSeen: [String: Date]
        var fromSnapshot: Bool
    }

    func loadHot() -> [Package]? { snapshots.loadHot() }
    func saveHot(_ packages: [Package]) { snapshots.saveHot(packages) }

    /// Instant path for launch: the last snapshot, whatever its age.
    func loadSnapshot() -> LoadResult? {
        guard let (catalog, _) = snapshots.loadCatalog() else { return nil }
        return LoadResult(catalog: catalog, firstSeen: snapshots.loadFirstSeen(), fromSnapshot: true)
    }

    /// Returns a fresh catalog if Homebrew's data changed since the snapshot, otherwise nil.
    func refreshIfNeeded(env: BrewEnvironment, force: Bool = false) async throws -> LoadResult? {
        let signpost = Perf.begin("catalog.refresh")
        defer { Perf.end(signpost) }
        let existing = snapshots.loadCatalog()?.1
        var catalog: Catalog
        var meta: SnapshotStore.Meta
        if let file = CatalogLoader.internalPackagesFile(cache: env.cache) {
            let modified = CatalogLoader.modDate(file)
            if !force, let existing, existing.sourcePath == file.path, existing.sourceModified == modified { return nil }
            catalog = try CatalogLoader.loadInternal(from: file)
            meta = .init(sourcePath: file.path, sourceModified: modified, savedAt: .now)
        } else if let legacy = legacyLocal(env: env) {
            if !force, let existing, existing.sourcePath == legacy.path, existing.sourceModified == legacy.modified { return nil }
            catalog = try CatalogLoader.parseLegacy(formulae: legacy.formulae, casks: legacy.casks, source: "api/*.jws.json")
            meta = .init(sourcePath: legacy.path, sourceModified: legacy.modified, savedAt: .now)
        } else {
            if !force, let existing, existing.sourcePath == "remote", existing.savedAt.timeIntervalSinceNow > -3600 * 6 { return nil }
            catalog = try await fetchRemote()
            meta = .init(sourcePath: "remote", sourceModified: .now, savedAt: .now)
        }
        catalog.packages += thirdPartyPackages(env: env)
        snapshots.save(catalog, meta: meta)

        let seed = SnapshotStore.seedFromHomebrewNameLists(cache: env.cache)
        let firstSeen = SnapshotStore.diff(
            previous: snapshots.loadFirstSeen(), currentIDs: catalog.packages.map(\.id), now: .now, seedNew: seed)
        snapshots.saveFirstSeen(firstSeen)
        Self.log.info("catalog loaded: \(catalog.packages.count) packages from \(meta.sourcePath, privacy: .public)")
        return LoadResult(catalog: catalog, firstSeen: firstSeen, fromSnapshot: false)
    }

    private func legacyLocal(env: BrewEnvironment) -> (formulae: Data?, casks: Data?, path: String, modified: Date)? {
        let f = env.cache.appending(path: "api/formula.jws.json")
        let c = env.cache.appending(path: "api/cask.jws.json")
        let fd = try? Data(contentsOf: f, options: .mappedIfSafe)
        let cd = try? Data(contentsOf: c, options: .mappedIfSafe)
        guard fd != nil || cd != nil else { return nil }
        return (fd, cd, f.path, max(CatalogLoader.modDate(f), CatalogLoader.modDate(c)))
    }

    // MARK: Remote

    private func fetchRemote() async throws -> Catalog {
        let base = NetworkSettings.apiBase
        async let f = fetch(URL(string: base + "/formula.json")!)
        async let c = fetch(URL(string: base + "/cask.json")!)
        return try CatalogLoader.parseLegacy(formulae: try await f, casks: try await c, source: "formulae.brew.sh")
    }

    /// GET with If-None-Match; on 304 returns the cached body.
    private func fetch(_ url: URL) async throws -> Data {
        let cacheFile = Paths.caches.appending(path: url.lastPathComponent)
        let etagKey = "etag:" + url.absoluteString
        var request = URLRequest(url: url, timeoutInterval: 30)
        if let etag = UserDefaults.standard.string(forKey: etagKey), FileManager.default.fileExists(atPath: cacheFile.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304, let cached = try? Data(contentsOf: cacheFile) { return cached }
        try? data.write(to: cacheFile, options: .atomic)
        if let etag = http?.value(forHTTPHeaderField: "ETag") { UserDefaults.standard.set(etag, forKey: etagKey) }
        return data
    }

    // MARK: Third-party taps

    /// Packages from installed non-core taps, by reading tap directories. The catalog has rich data
    /// only for official taps; for others we record the name, tap and file path so they are
    /// searchable and installable. Descriptions are scraped from the Ruby `desc "..."` line.
    private func thirdPartyPackages(env: BrewEnvironment) -> [Package] {
        let fm = FileManager.default
        var result: [Package] = []
        let users = (try? fm.contentsOfDirectory(atPath: env.tapsDir.path)) ?? []
        for user in users where !user.hasPrefix(".") {
            let userDir = env.tapsDir.appending(path: user)
            for repo in (try? fm.contentsOfDirectory(atPath: userDir.path)) ?? [] where repo.hasPrefix("homebrew-") {
                let tap = "\(user)/\(repo.dropFirst("homebrew-".count))"
                if tap.hasPrefix("homebrew/") { continue }
                let tapDir = userDir.appending(path: repo)
                for (kind, sub) in [(PackageKind.formula, "Formula"), (.cask, "Casks")] {
                    let dir = tapDir.appending(path: sub)
                    let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil)
                    while let file = e?.nextObject() as? URL {
                        guard file.pathExtension == "rb" else { continue }
                        let token = file.deletingPathExtension().lastPathComponent
                        let (desc, homepage, version) = Self.scrapeRuby(file)
                        result.append(Package(
                            kind: kind, token: token, fullName: "\(tap)/\(token)", displayName: token,
                            desc: desc, homepage: homepage, version: version, tap: tap))
                    }
                }
            }
        }
        return result
    }

    static func scrapeRuby(_ file: URL) -> (String, String, String) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return ("", "", "") }
        func value(_ key: String) -> String {
            for line in text.split(separator: "\n").prefix(40) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix(key + " \"") else { continue }
                return String(t.dropFirst(key.count + 2).prefix { $0 != "\"" })
            }
            return ""
        }
        return (value("desc"), value("homepage"), value("version"))
    }
}
