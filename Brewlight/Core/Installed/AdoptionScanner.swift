import Foundation

/// An app installed outside Homebrew that a cask could take over (`brew install --cask --adopt`).
struct AdoptableApp: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var name: String
    var token: String
    var appVersion: String?
    var caskVersion: String
    var bundleID: String?
    var isAppStore: Bool

    /// Cask versions can carry a build suffix ("1.2.3,4567"); compare the part before the comma.
    var versionMatches: Bool {
        guard caskVersion != "latest" else { return true }
        guard let v = appVersion, !v.isEmpty else { return false }
        let cask = caskVersion.split(separator: ",").first.map(String.init) ?? caskVersion
        return v == cask || BrewVersion(v) == BrewVersion(cask)
    }

    enum Status: Sendable { case ready, versionDiffers, appStore }
    var status: Status { isAppStore ? .appStore : (versionMatches ? .ready : .versionDiffers) }
}

enum AdoptionScanner {
    /// What we read from an app bundle.
    struct AppBundle: Sendable, Hashable {
        var path: String
        var fileName: String
        var version: String?
        var bundleID: String?
        var isAppStore: Bool
    }

    static let folders: [URL] = [URL(fileURLWithPath: "/Applications"), URL.homeDirectory.appending(path: "Applications")]

    /// Top-level `.app` bundles in the Applications folders. Call off the main thread.
    static func scanBundles(in folders: [URL] = folders) -> [AppBundle] {
        let fm = FileManager.default
        var out: [AppBundle] = []
        for folder in folders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist")) as? [String: Any]
                out.append(AppBundle(
                    path: url.resolvingSymlinksInPath().path,
                    fileName: url.lastPathComponent,
                    version: info?["CFBundleShortVersionString"] as? String,
                    bundleID: info?["CFBundleIdentifier"] as? String,
                    isAppStore: fm.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path)))
            }
        }
        return out
    }

    /// Matches app bundles to casks by the `.app` name each cask installs.
    /// Skips Apple's apps, apps a cask already manages, and casks that are already installed.
    static func match(bundles: [AppBundle], casks: [Package], installedCasks: Set<String>, managedPaths: Set<String>) -> [AdoptableApp] {
        var byAppName: [String: [Package]] = [:]
        for c in casks where c.kind == .cask && !c.isDisabled {
            for app in c.appNames {
                let name = (app as NSString).lastPathComponent
                byAppName[name.lowercased(), default: []].append(c)
            }
        }
        var out: [AdoptableApp] = []
        for b in bundles {
            if b.bundleID?.hasPrefix("com.apple.") == true { continue }
            if managedPaths.contains(b.path) { continue }
            guard let candidates = byAppName[b.fileName.lowercased()] else { continue }
            if candidates.contains(where: { installedCasks.contains($0.token) }) { continue }
            // Prefer the main cask over variants (e.g. firefox over firefox@beta).
            let pick = candidates.min { a, z in
                let av = a.token.contains("@"), zv = z.token.contains("@")
                return av != zv ? !av : a.token.count < z.token.count
            }!
            let name = (b.fileName as NSString).deletingPathExtension
            // One row per cask: a cask that installs several apps (e.g. openra) is adopted once.
            if let i = out.firstIndex(where: { $0.token == pick.token }) {
                out[i].name += ", " + name
                out[i].isAppStore = out[i].isAppStore || b.isAppStore
                continue
            }
            out.append(AdoptableApp(path: b.path, name: name, token: pick.token,
                                    appVersion: b.version, caskVersion: pick.version, bundleID: b.bundleID, isAppStore: b.isAppStore))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
