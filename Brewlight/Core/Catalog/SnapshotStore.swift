import Foundation

/// Persists a compact copy of the catalog so launch never has to re-parse Homebrew's 15 MB JSON,
/// and tracks when each package was first seen so "New in Homebrew" works offline.
struct SnapshotStore: Sendable {
    let directory: URL

    struct Meta: Codable, Sendable {
        var sourcePath: String
        var sourceModified: Date
        var savedAt: Date
    }

    private var catalogURL: URL { directory.appending(path: "catalog.plist") }
    private var metaURL: URL { directory.appending(path: "catalog-meta.plist") }
    private var firstSeenURL: URL { directory.appending(path: "first-seen.plist") }
    private var hotURL: URL { directory.appending(path: "catalog-hot.plist") }

    func loadCatalog() -> (Catalog, Meta)? {
        guard let data = try? Data(contentsOf: catalogURL, options: .mappedIfSafe),
              let metaData = try? Data(contentsOf: metaURL),
              let catalog = try? PropertyListDecoder().decode(Catalog.self, from: data),
              let meta = try? PropertyListDecoder().decode(Meta.self, from: metaData) else { return nil }
        return (catalog, meta)
    }

    func save(_ catalog: Catalog, meta: Meta) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(catalog) { try? data.write(to: catalogURL, options: .atomic) }
        if let data = try? encoder.encode(meta) { try? data.write(to: metaURL, options: .atomic) }
    }

    // MARK: Hot subset

    /// A few hundred packages (the installed ones) that decode in a couple of milliseconds, so the
    /// Installed list is on screen long before the full ~16k-package snapshot finishes loading.
    func loadHot() -> [Package]? {
        let t = Perf.begin("load.hot")
        defer { Perf.end(t) }
        guard let data = try? Data(contentsOf: hotURL) else { return nil }
        return try? PropertyListDecoder().decode([Package].self, from: data)
    }

    func saveHot(_ packages: [Package]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(packages) { try? data.write(to: hotURL, options: .atomic) }
    }

    // MARK: First seen

    func loadFirstSeen() -> [String: Date] {
        guard let data = try? Data(contentsOf: firstSeenURL) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    func saveFirstSeen(_ map: [String: Date]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(map) { try? data.write(to: firstSeenURL, options: .atomic) }
    }

    /// Records new package IDs. On the very first run there is no previous token set, so every
    /// package gets `.distantPast` (not "new"), except IDs in `seedNew`, which get `now`.
    static func diff(previous: [String: Date], currentIDs: [String], now: Date, seedNew: Set<String>) -> [String: Date] {
        var result = previous
        let firstRun = previous.isEmpty
        for id in currentIDs where result[id] == nil {
            if firstRun {
                result[id] = seedNew.contains(id) ? now : .distantPast
            } else {
                result[id] = now
            }
        }
        // Keep dates only for packages that still exist, so removed IDs don't pile up forever.
        // An empty current list means the catalog failed to load — leave the map alone.
        let current = Set(currentIDs)
        if !current.isEmpty { result = result.filter { current.contains($0.key) } }
        return result
    }

    /// First-launch seed: Homebrew itself keeps `formula_names.before.txt` / `formula_names.txt`
    /// (and the cask equivalents) to print "New Formulae" after `brew update`. Diffing them gives
    /// the packages added in the most recent update without any network call.
    static func seedFromHomebrewNameLists(cache: URL) -> Set<String> {
        var result = Set<String>()
        let api = cache.appending(path: "api")
        for (kind, base) in [(PackageKind.formula, "formula_names"), (.cask, "cask_names")] {
            guard let before = try? String(contentsOf: api.appending(path: "\(base).before.txt"), encoding: .utf8),
                  let after = try? String(contentsOf: api.appending(path: "\(base).txt"), encoding: .utf8) else { continue }
            let old = Set(before.split(separator: "\n").map(String.init))
            for name in after.split(separator: "\n") where !old.contains(String(name)) {
                result.insert(Package.id(kind, String(name)))
            }
        }
        return result
    }
}
