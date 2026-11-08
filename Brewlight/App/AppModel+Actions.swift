import AppKit
import Foundation

/// One `brew` invocation, built before it runs so it can be shown first.
struct BrewCommand: Hashable, Sendable {
    var title: String
    var args: [String]
    var packages: [String]

    init(_ title: String, _ args: [String], packages: [String] = []) {
        self.title = title
        self.args = args
        self.packages = packages
    }

    /// As you'd type it in Terminal.
    var display: String { (["brew"] + args.map(Self.quote)).joined(separator: " ") }

    static func quote(_ s: String) -> String {
        s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./@:=+,".contains($0) }) ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct InstallOptions: Equatable, Sendable {
    var buildFromSource = false
    var head = false
    var force = false
}

/// A file or folder that a removal would delete, shown to the user before anything happens.
struct RemovalItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    var url: URL
    var size: Int64
    var isSelected = true
}

extension AppModel {
    // MARK: Commands
    //
    // Every action builds its `brew` invocations here first. Confirmation sheets show exactly these
    // commands, and the same values are what runs, so the preview can never drift from reality.

    func installCommands(_ ids: [String], options: InstallOptions = .init()) -> [BrewCommand] {
        let pkgs = ids.compactMap(package)
        let formulae = pkgs.filter { $0.kind == .formula }.map { $0.isOfficial ? $0.token : $0.fullName }
        let casks = pkgs.filter { $0.kind == .cask }.map { $0.isOfficial ? $0.token : $0.fullName }
        var flags: [String] = []
        if options.buildFromSource { flags.append("--build-from-source") }
        if options.head { flags.append("--HEAD") }
        if options.force { flags.append("--force") }
        var out: [BrewCommand] = []
        if !formulae.isEmpty {
            out.append(BrewCommand(title(String(localized: "Install"), formulae), ["install", "--formula"] + flags + formulae, packages: formulae))
        }
        if !casks.isEmpty {
            out.append(BrewCommand(title(String(localized: "Install"), casks), ["install", "--cask"] + (options.force ? ["--force"] : []) + casks, packages: casks))
        }
        return out
    }

    func reinstallCommand(_ id: String) -> BrewCommand? {
        guard let p = package(id) else { return nil }
        return BrewCommand(title(String(localized: "Reinstall"), [p.token]), ["reinstall", p.kind.flag, p.token], packages: [p.token])
    }

    func uninstallCommand(_ id: String, ignoreDependencies: Bool = false, allVersions: Bool = false, zap: Bool = false) -> BrewCommand? {
        guard let p = package(id) ?? installed[id].map(packageOrStub) else { return nil }
        var args = ["uninstall", p.kind.flag]
        if ignoreDependencies { args.append("--ignore-dependencies") }
        if allVersions || zap { args.append("--force") }
        if zap { args.append("--zap") }
        args.append(p.token)
        let verb = zap ? String(localized: "Remove completely") : String(localized: "Uninstall")
        return BrewCommand(title(verb, [p.token]), args, packages: [p.token])
    }

    func upgradeCommands(_ ids: [String]) -> [BrewCommand] {
        let infos = ids.compactMap { visibleOutdated[$0] }.filter { !$0.pinned }
        let formulae = infos.filter { $0.kind == .formula }.map(\.token).sorted()
        let casks = infos.filter { $0.kind == .cask }.map(\.token).sorted()
        var out: [BrewCommand] = []
        if !formulae.isEmpty { out.append(BrewCommand(title(String(localized: "Upgrade"), formulae), ["upgrade", "--formula"] + formulae, packages: formulae)) }
        if !casks.isEmpty {
            var args = ["upgrade", "--cask"]
            if UserDefaults.standard.bool(forKey: "greedyCasks") { args.append("--greedy") }
            out.append(BrewCommand(title(String(localized: "Upgrade"), casks), args + casks, packages: casks))
        }
        return out
    }

    var upgradeAllCommands: [BrewCommand] { upgradeCommands(visibleOutdated.values.filter { !$0.pinned }.map(\.id)) }

    @discardableResult
    func run(_ commands: [BrewCommand], showActivity show: Bool = true) -> [BrewOperation] {
        let ops = commands.map { operations.enqueue($0.title, $0.args, packages: $0.packages) }
        if show && !commands.isEmpty { showActivity = true }
        return ops
    }

    // MARK: Install / uninstall / upgrade

    func install(_ ids: [String], options: InstallOptions = .init()) {
        run(installCommands(ids, options: options))
    }

    func reinstall(_ id: String) {
        run(reinstallCommand(id).map { [$0] } ?? [])
    }

    func uninstall(_ id: String, ignoreDependencies: Bool = false, allVersions: Bool = false, zap: Bool = false) {
        run(uninstallCommand(id, ignoreDependencies: ignoreDependencies, allVersions: allVersions, zap: zap).map { [$0] } ?? [])
    }

    func upgrade(_ ids: [String]) {
        run(upgradeCommands(ids))
    }

    /// Upgrades everything visible on the Updates page except pinned and skipped packages.
    func upgradeAll() {
        let ids = visibleOutdated.values.filter { !$0.pinned }.map(\.id)
        guard !ids.isEmpty else { toast(String(localized: "Everything is up to date")); return }
        upgrade(ids)
    }

    /// "Update" refreshes Homebrew's metadata; it never upgrades packages.
    func updateHomebrew() {
        operations.enqueue(String(localized: "Update Homebrew"), ["update"], packages: [])
    }

    func pin(_ id: String, _ on: Bool) {
        guard let p = package(id), p.kind == .formula else { return }
        operations.enqueue(title(on ? String(localized: "Pin") : String(localized: "Unpin"), [p.token]), [on ? "pin" : "unpin", p.token], packages: [p.token])
    }

    func link(_ id: String, _ on: Bool) {
        guard let p = package(id), p.kind == .formula else { return }
        operations.enqueue(title(on ? String(localized: "Link") : String(localized: "Unlink"), [p.token]), [on ? "link" : "unlink", p.token], packages: [p.token])
    }

    func autoremove() {
        operations.enqueue(String(localized: "Remove unused dependencies"), ["autoremove"])
        showActivity = true
    }

    private func title(_ verb: String, _ names: [String]) -> String {
        names.count == 1 ? "\(verb) \(names[0])" : String(localized: "\(verb) \(names.count) packages")
    }

    // MARK: Previews (read-only)

    /// New packages an install would bring in, from the catalog graph.
    func newDependencies(for ids: [String]) -> [String] {
        let have = installedFormulaNames
        var result: [String] = []
        var seen = Set<String>()
        for id in ids {
            guard let p = package(id) else { continue }
            let deps = p.kind == .formula ? graph.transitiveDependencies(of: p.token)
                : p.caskFormulaDependencies.flatMap { [$0] + graph.transitiveDependencies(of: $0) }
            for d in deps where !have.contains(d) && seen.insert(d).inserted { result.append(d) }
        }
        return result
    }

    /// Installed packages that need this one.
    func dependents(of id: String) -> [String] {
        guard let p = package(id) ?? installed[id].map(packageOrStub) else { return [] }
        var installedIDs = installedFormulaNames
        for i in installed.values where i.kind == .cask { installedIDs.insert("cask:" + i.token) }
        if p.kind == .formula {
            // Receipts are authoritative for what was actually linked against.
            var fromReceipts = Set<String>()
            for i in installed.values where i.runtimeDependencies.contains(where: { $0 == p.token || $0.hasSuffix("/" + p.token) }) {
                fromReceipts.insert(i.token)
            }
            return Array(fromReceipts.union(graph.dependents(of: p.token, installed: installedIDs))).sorted()
        }
        return []
    }

    /// Existing zap paths for a cask, with sizes.
    func zapItems(for id: String) async -> [RemovalItem] {
        guard let p = package(id) else { return [] }
        let paths = p.zapPaths
        return await Task.detached(priority: .userInitiated) {
            paths.flatMap(Paths.expandExisting).map { RemovalItem(url: $0, size: Paths.diskSize($0)) }
        }.value
    }

    /// Config, data, logs and launch agents a formula leaves behind after uninstall.
    func leftoverItems(for id: String) async -> [RemovalItem] {
        guard let env, let p = package(id) ?? installed[id].map(packageOrStub), p.kind == .formula else { return [] }
        let name = p.token
        let base = name.split(separator: "@").first.map(String.init) ?? name
        let prefix = env.prefix
        return await Task.detached(priority: .userInitiated) {
            var patterns = ["etc/\(base)*", "var/\(base)*", "var/log/\(base)*", "var/lib/\(base)*", "share/\(base)*"]
                .map { prefix.appending(path: $0).path }
            patterns.append("~/Library/LaunchAgents/homebrew.mxcl.\(name).plist")
            patterns.append("~/Library/LaunchAgents/homebrew.mxcl.\(base).plist")
            var seen = Set<String>()
            return patterns.flatMap(Paths.expandExisting)
                .filter { seen.insert($0.path).inserted && !$0.path.hasPrefix(prefix.appending(path: "Cellar").path) }
                .map { RemovalItem(url: $0, size: Paths.diskSize($0)) }
        }.value
    }

    /// Moves to Trash by default; deletes permanently only when the setting says so.
    func remove(_ items: [RemovalItem]) {
        let permanently = UserDefaults.standard.bool(forKey: "deletePermanently")
        var failed: [String] = []
        for item in items where item.isSelected {
            do {
                if permanently { try FileManager.default.removeItem(at: item.url) }
                else { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
            } catch {
                failed.append(item.url.path)
            }
        }
        let op = BrewOperation(title: String(localized: "Remove leftover files"), args: ["(file removal)"], packages: items.map(\.url.lastPathComponent), isMutating: true)
        op.replaceLog(items.filter(\.isSelected).map { OutputLine(stream: .stdout, text: (permanently ? "Deleted " : "Moved to Trash: ") + $0.url.path) }
            + failed.map { OutputLine(stream: .stderr, text: "Error: Could not remove \($0)") })
        op.startedAt = .now; op.finishedAt = .now
        op.state = failed.isEmpty ? .succeeded : .failed(1)
        userData.record(op)
        if !failed.isEmpty { toast(String(localized: "Some files could not be removed"), error: true) }
    }

    // MARK: Versions

    /// Installed formulae that are versions of the same software (python@3.14, python@3.15, …).
    func versionFamily(of p: Package) -> [InstalledPackage] {
        guard p.kind == .formula else { return [] }
        let base = p.token.split(separator: "@").first.map(String.init) ?? p.token
        let family = installed.values.filter { $0.kind == .formula && ($0.token == base || $0.token.hasPrefix(base + "@")) }
        return family.count > 1 ? family.sorted { BrewVersion($0.currentVersion) > BrewVersion($1.currentVersion) } : []
    }

    /// Makes one family member the one on PATH: unlink the others, then link it (`--force` for
    /// keg-only versioned formulae, which Homebrew doesn't link by default).
    func switchVersionCommands(to id: String) -> [BrewCommand] {
        guard let p = package(id) ?? installed[id].map(packageOrStub) else { return [] }
        let others = versionFamily(of: p).filter { $0.token != p.token && $0.linkedIntoPrefix == true }
        var out = others.map { BrewCommand(String(localized: "Unlink \($0.token)"), ["unlink", $0.token], packages: [$0.token]) }
        out.append(BrewCommand(String(localized: "Link \(p.token)"), ["link"] + (p.kegOnly ? ["--force"] : []) + [p.token], packages: [p.token]))
        return out
    }

    /// Older kegs of one formula (Cellar/node/24.9.0 next to 24.11.0) and its stale downloads.
    func removeOldVersionsCommand(_ id: String) -> BrewCommand? {
        guard let inst = installed[id], inst.kind == .formula, inst.versions.count > 1 else { return nil }
        return BrewCommand(String(localized: "Remove old versions of \(inst.token)"), ["cleanup", inst.token], packages: [inst.token])
    }

    // MARK: Download cache

    func cacheEntries(for id: String) async -> [PackageCache.Entry] {
        guard let env, let p = package(id) ?? installed[id].map(packageOrStub) else { return [] }
        return await Task.detached(priority: .userInitiated) { PackageCache.entries(for: p, cache: env.cache) }.value
    }

    func clearCache(_ entries: [PackageCache.Entry], for token: String) {
        let failed = PackageCache.remove(entries)
        let op = BrewOperation(title: String(localized: "Clear download cache for \(token)"), args: ["(cache removal)"], packages: [token], isMutating: true)
        op.replaceLog(entries.compactMap { $0.file ?? $0.link }.map { OutputLine(stream: .stdout, text: "Deleted " + $0.path) }
                      + failed.map { OutputLine(stream: .stderr, text: "Error: Could not remove \($0)") })
        op.startedAt = .now; op.finishedAt = .now
        op.state = failed.isEmpty ? .succeeded : .failed(1)
        userData.record(op)
        toast(failed.isEmpty ? String(localized: "Freed \(PackageCache.totalSize(entries).byteString)") : String(localized: "Some cached files could not be removed"), error: !failed.isEmpty)
    }

    // MARK: Finder, URLs, clipboard

    func open(_ id: String) {
        guard let path = installed[id]?.appPaths.first else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func showInFinder(_ id: String) {
        guard let env, let inst = installed[id] else { return }
        let url: URL
        if let app = inst.appPaths.first { url = URL(fileURLWithPath: app) }
        else if inst.kind == .formula { url = env.cellar.appending(path: inst.token).appending(path: inst.currentVersion) }
        else { url = env.caskroom.appending(path: inst.token) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast(String(localized: "Copied to clipboard"))
    }

    // MARK: Services

    func service(_ action: String, _ name: String) {
        operations.enqueue("\(action.capitalized) \(name)", ["services", action, name], packages: [name])
    }

    // MARK: Taps

    func addTap(_ name: String) {
        let parts = name.split(separator: " ").map(String.init)
        operations.enqueue(String(localized: "Add tap \(parts[0])"), ["tap"] + parts, packages: [parts[0]])
    }

    func removeTap(_ name: String) {
        operations.enqueue(String(localized: "Remove tap \(name)"), ["untap", name], packages: [name])
    }

    // MARK: Terminal fallback

    /// Opens Terminal with the exact command, for steps that need a TTY.
    func runInTerminal(_ command: String) {
        let script = "#!/bin/zsh\n\(command)\necho\necho 'Done. You can close this window.'\n"
        let url = FileManager.default.temporaryDirectory.appending(path: "brewlight-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            toast(error.localizedDescription, error: true)
        }
    }
}
