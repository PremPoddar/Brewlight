import Foundation

/// What is on disk for one installed formula or cask.
struct InstalledPackage: Codable, Sendable, Hashable, Identifiable {
    var id: String { Package.id(kind, token) }
    var kind: PackageKind
    var token: String
    /// All installed versions (kegs), newest last.
    var versions: [String]
    var linkedVersion: String?
    var installedOnRequest: Bool
    var installedAsDependency: Bool
    var pouredFromBottle: Bool
    var installedAt: Date?
    var runtimeDependencies: [String]
    var tap: String?
    var isPinned: Bool
    /// For casks: resolved `.app` bundle paths that exist.
    var appPaths: [String] = []
    /// Formula only: symlinked into the prefix (`var/homebrew/linked/<name>`), i.e. its commands are on PATH.
    var linkedIntoPrefix: Bool? = nil

    var currentVersion: String { linkedVersion ?? versions.last ?? "" }
}

/// Reads installed state straight from the Cellar, Caskroom and pinned directories.
/// Much faster than `brew info --installed`, which is used only to cross-check.
enum InstalledScanner {
    static func scan(env: BrewEnvironment, catalogApps: [String: [String]]) -> [InstalledPackage] {
        scanFormulae(env: env) + scanCasks(env: env, catalogApps: catalogApps)
    }

    static func scanFormulae(env: BrewEnvironment) -> [InstalledPackage] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: env.cellar.path)) ?? []
        let pinned = Set((try? fm.contentsOfDirectory(atPath: env.pinnedDir.path)) ?? [])
        let linkedKegs = Set((try? fm.contentsOfDirectory(atPath: env.prefix.appending(path: "var/homebrew/linked").path)) ?? [])
        var result: [InstalledPackage] = []
        for name in names where !name.hasPrefix(".") {
            let dir = env.cellar.appending(path: name)
            let versions = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted { BrewVersion($0) < BrewVersion($1) }
            guard let latest = versions.last else { continue }
            let linked = (try? fm.destinationOfSymbolicLink(atPath: env.optDir.appending(path: name).path))
                .map { ($0 as NSString).lastPathComponent }
            let keg = linked.flatMap { versions.contains($0) ? $0 : nil } ?? latest
            let receipt = Receipt.read(dir.appending(path: keg).appending(path: "INSTALL_RECEIPT.json"))
            result.append(InstalledPackage(
                kind: .formula, token: name, versions: versions, linkedVersion: linked,
                installedOnRequest: receipt?.installedOnRequest ?? true,
                installedAsDependency: receipt?.installedAsDependency ?? false,
                pouredFromBottle: receipt?.pouredFromBottle ?? true,
                installedAt: receipt?.time,
                runtimeDependencies: receipt?.runtimeDependencies ?? [],
                tap: receipt?.tap,
                isPinned: pinned.contains(name),
                linkedIntoPrefix: linkedKegs.contains(name)))
        }
        return result
    }

    static func scanCasks(env: BrewEnvironment, catalogApps: [String: [String]]) -> [InstalledPackage] {
        let fm = FileManager.default
        let tokens = (try? fm.contentsOfDirectory(atPath: env.caskroom.path)) ?? []
        var result: [InstalledPackage] = []
        for token in tokens where !token.hasPrefix(".") {
            let dir = env.caskroom.appending(path: token)
            let versions = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted { BrewVersion($0) < BrewVersion($1) }
            guard !versions.isEmpty else { continue }
            let receipt = Receipt.read(dir.appending(path: ".metadata/INSTALL_RECEIPT.json"))
            var apps = receipt?.appNames ?? []
            if apps.isEmpty { apps = catalogApps[token] ?? [] }
            let appPaths = apps.compactMap { name -> String? in
                let candidates = name.hasPrefix("/") ? [name] : ["/Applications/\(name)", ("~/Applications/\(name)" as NSString).expandingTildeInPath]
                return candidates.first { fm.fileExists(atPath: $0) }
            }
            result.append(InstalledPackage(
                kind: .cask, token: token, versions: versions, linkedVersion: nil,
                installedOnRequest: receipt?.installedOnRequest ?? true,
                installedAsDependency: receipt?.installedAsDependency ?? false,
                pouredFromBottle: true,
                installedAt: receipt?.time ?? (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate),
                runtimeDependencies: [],
                tap: receipt?.tap,
                isPinned: false,
                appPaths: appPaths))
        }
        return result
    }
}

/// The subset of `INSTALL_RECEIPT.json` the app uses. Both formula and cask receipts.
struct Receipt: Sendable, Equatable {
    var installedOnRequest: Bool?
    var installedAsDependency: Bool?
    var pouredFromBottle: Bool?
    var time: Date?
    var runtimeDependencies: [String]
    var tap: String?
    var appNames: [String]

    static func read(_ url: URL) -> Receipt? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Receipt? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var deps: [String] = []
        if let arr = obj["runtime_dependencies"] as? [[String: Any]] {
            deps = arr.compactMap { $0["full_name"] as? String }
        }
        var apps: [String] = []
        for case let dict as [String: Any] in obj["uninstall_artifacts"] as? [Any] ?? [] {
            if let a = dict["app"] { apps += CatalogLoader.stringList(a) }
        }
        let source = obj["source"] as? [String: Any]
        return Receipt(
            installedOnRequest: obj["installed_on_request"] as? Bool,
            installedAsDependency: obj["installed_as_dependency"] as? Bool,
            pouredFromBottle: obj["poured_from_bottle"] as? Bool,
            time: (obj["time"] as? Double).map { Date(timeIntervalSince1970: $0) },
            runtimeDependencies: deps,
            tap: source?["tap"] as? String,
            appNames: apps)
    }
}
