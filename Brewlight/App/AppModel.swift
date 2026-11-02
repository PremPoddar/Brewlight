import AppKit
import Foundation
import Observation
import os

struct OutdatedInfo: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var kind: PackageKind
    var token: String
    var installed: String
    var available: String
    var pinned: Bool
}

enum SidebarItem: Hashable, Codable, Sendable {
    case discover, installed, updates, adopt, services, taps
    case allPackages, categories, favourites, leaves, newPackages
    case category(String)
    case tag(String)
    case history, maintenance, brewfile

    var title: String {
        switch self {
        case .discover: String(localized: "Discover")
        case .installed: String(localized: "Installed")
        case .updates: String(localized: "Updates")
        case .adopt: String(localized: "Adopt Apps")
        case .services: String(localized: "Services")
        case .taps: String(localized: "Taps")
        case .allPackages: String(localized: "All Packages")
        case .categories: String(localized: "Categories")
        case .favourites: String(localized: "Favourites")
        case .leaves: String(localized: "Leaves")
        case .newPackages: String(localized: "New in Homebrew")
        case .category(let c): PackageCategory(rawValue: c)?.localizedName ?? c
        case .tag(let t): t
        case .history: String(localized: "History")
        case .maintenance: String(localized: "Maintenance")
        case .brewfile: String(localized: "Brewfile")
        }
    }

    var symbol: String {
        switch self {
        case .discover: "sparkles"
        case .installed: "shippingbox"
        case .updates: "arrow.up.circle"
        case .adopt: "arrow.down.app"
        case .services: "dot.radiowaves.left.and.right"
        case .taps: "point.3.connected.trianglepath.dotted"
        case .allPackages: "square.stack.3d.up"
        case .categories: "square.grid.2x2"
        case .favourites: "star"
        case .leaves: "leaf"
        case .newPackages: "seal"
        case .category(let c): PackageCategory(rawValue: c)?.symbol ?? "folder"
        case .tag: "tag"
        case .history: "clock.arrow.circlepath"
        case .maintenance: "stethoscope"
        case .brewfile: "doc.text"
        }
    }

    /// Order for ⌘1…⌘9.
    static let numbered: [SidebarItem] = [.discover, .installed, .updates, .services, .taps, .allPackages, .categories, .history, .maintenance]
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case locating, missingBrew, ready }

    // MARK: Stores
    let operations = OperationCenter()
    let userData: UserDataStore
    let updater = AppUpdater()
    private let catalogStore = CatalogStore()
    private let popularityStore = PopularityStore()
    private(set) var categories = CategoryStore()

    // MARK: State
    private(set) var phase: Phase = .locating
    private(set) var env: BrewEnvironment?
    private(set) var runner: (any BrewRunning)?

    private(set) var packages: [Package] = [] { didSet { dataVersion &+= 1 } }
    /// Bumped whenever anything a package list depends on changes; list views key their caches on it.
    private(set) var dataVersion = 0
    private(set) var indexByID: [String: Int] = [:]
    private(set) var searchIndex = SearchIndex(packages: [])
    private(set) var graph = DependencyGraph(packages: [])
    private(set) var formulaAliases: [String: String] = [:]
    private(set) var catalogGeneratedAt: Date?
    private(set) var catalogLoadedAt: Date?
    private(set) var catalogError: String?
    private(set) var isRefreshingCatalog = false

    private(set) var installed: [String: InstalledPackage] = [:] {
        didSet { dataVersion &+= 1; scheduleStateSave() }
    }
    private(set) var outdated: [String: OutdatedInfo] = [:] {
        didSet { recomputeVisibleOutdated(); scheduleStateSave() }
    }
    /// Outdated minus skipped versions. Stored (not computed) because every row reads it.
    private(set) var visibleOutdated: [String: OutdatedInfo] = [:] { didSet { dataVersion &+= 1 } }
    private(set) var outdatedCheckedAt: Date?
    private(set) var isCheckingOutdated = false
    private(set) var popularity = Popularity() { didSet { rebuildRankings() } }
    /// installs30 per catalog index, for search ranking without string lookups.
    private(set) var popularityByIndex: [Int] = []
    /// Catalog indices by 30-day installs, most popular first (top 2,000).
    private(set) var popularRanking: [Int] = []
    /// Catalog indices with their growth, fastest-growing (weighted by volume) first.
    private(set) var trendingRanking: [(index: Int, trend: Double)] = []
    /// Precomputed full orders for the analytics sorts (see `Rankings.orders`).
    private(set) var sortOrders: [SortOrder: [Int]] = [:]
    private(set) var firstSeen: [String: Date] = [:] { didSet { dataVersion &+= 1 } }
    /// Packages first seen in the last 30 days, newest first.
    private(set) var recentPackages: [(index: Int, date: Date)] = []
    private(set) var newThisWeekCount = 0
    private(set) var formulaCount = 0
    private(set) var caskCount = 0
    private(set) var sizes: [String: Int64] = [:] { didSet { scheduleStateSave() } }
    private var isComputingSizes = false
    private(set) var services: [BrewService] = [] { didSet { scheduleStateSave() } }
    private(set) var taps: [BrewTap] = [] { didSet { scheduleStateSave() } }
    private var stateSaveTask: Task<Void, Never>?
    /// False until a full catalog (snapshot, fresh parse, or demo) is in memory; the hot subset doesn't count.
    private(set) var hasFullCatalog = false
    var isCatalogLoading: Bool { !hasFullCatalog && catalogError == nil }

    /// Cached category per package index, rebuilt with the catalog.
    private(set) var categoryOf: [PackageCategory] = []
    private(set) var categoryIsAuto: [Bool] = []
    private(set) var categoryCounts: [PackageCategory: Int] = [:]

    // MARK: Navigation
    var sidebar: SidebarItem = .discover {
        didSet { if sidebar != oldValue { recordNavigation(.section(sidebar)) } }
    }
    var selectedPackageID: String? {
        didSet { if let id = selectedPackageID, id != oldValue { recordNavigation(.package(id)) } }
    }
    var showPalette = false
    /// Text the palette opens with (e.g. from the snapshot hook).
    var paletteSeed = ""
    var showActivity = false
    var showPerfHUD = false
    var searchText = ""
    var pendingSheet: SheetRequest?

    // Maintenance results live here so they survive switching sections and can be started from
    // anywhere (the palette, menus).
    /// Apps installed outside Homebrew that a cask can take over.
    private(set) var adoptable: [AdoptableApp] = []
    private(set) var isScanningAdoptable = false
    private(set) var adoptableScannedAt: Date?

    private(set) var doctorWarnings: [MaintenanceParsers.DoctorWarning]?
    private(set) var isRunningDoctor = false
    private(set) var doctorRanAt: Date?
    private(set) var cleanupPreview: MaintenanceParsers.CleanupPreview?
    private(set) var isPreviewingCleanup = false
    var cleanupPruneAll = false
    /// A notice from brew's output waiting for the user's decision (shown as an alert).
    var pendingNotice: OperationNotice?
    /// Taps already asked about this session, so a repeated warning doesn't nag.
    private var promptedTaps: Set<String> = []
    static let tapTrustDocs = URL(string: "https://docs.brew.sh/Tap-Trust")!
    var toasts: [Toast] = []

    enum NavEntry: Hashable { case section(SidebarItem), package(String) }
    private var navStack: [NavEntry] = []
    private var navIndex = -1
    private var isNavigating = false

    private var watcher: FSEventsWatcher?
    private var rescanTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.example.brewlight", category: "model")

    init() {
        userData = UserDataStore(inMemory: AppInfo.isDemo)
        operations.onFinish = { [weak self] op in self?.operationFinished(op) }
        operations.onNotice = { [weak self] _, notice in self?.handle(notice) }
        userData.onChange = { [weak self] in
            self?.recomputeVisibleOutdated()
            self?.dataVersion &+= 1
        }
    }

    // MARK: Startup

    /// Launch never waits on Homebrew: the last-known state (installed packages, updates, sizes,
    /// services, taps, and the catalog subset for them) is on screen in a few milliseconds, then
    /// everything is refreshed in the background.
    func start() async {
        let t = Perf.begin("launch.model")
        if AppInfo.isDemo {
            loadDemo()
            Perf.end(t)
            return
        }

        // 1. Last-known state + hot catalog subset, decoded off the main thread.
        let loadT = Perf.begin("launch.loadCached")
        async let stateLoad = Task.detached(priority: .userInitiated) { StateSnapshot.load() }.value
        async let hotLoad = catalogStore.loadHot()
        let (state, hot) = await (stateLoad, hotLoad)
        Perf.end(loadT)
        if let hot, !hot.isEmpty {
            await apply(Catalog(packages: hot, formulaAliases: [:], generatedAt: nil, sourceDescription: "hot"), firstSeen: [:])
        }
        if let state {
            restore(state)
            if let env = state.env, FileManager.default.isExecutableFile(atPath: env.brew.path) {
                configure(env: env)
                phase = .ready
            }
        }
        Perf.end(t)

        // 2. Full catalog for search and Discover.
        Task {
            let full = Perf.begin("catalog.snapshot")
            if let snap = await catalogStore.loadSnapshot() {
                await apply(snap.catalog, firstSeen: snap.firstSeen)
                if outdatedCheckedAt == nil { recomputeOutdatedLocally() }
                saveHotSnapshot()
            }
            Perf.end(full)
            if let cached = await popularityStore.cached() { popularity = cached }
        }

        // 3. Verify Homebrew and refresh everything from disk and brew.
        let override = UserDefaults.standard.string(forKey: BrewLocator.overrideKey)
        guard let env = await BrewLocator.locate(override: override) else {
            phase = .missingBrew
            return
        }
        if self.env != env { configure(env: env) }
        phase = .ready
        await rescanInstalled()
        // Sizes come from the last-known state; refresh them later at low priority (it walks the Cellar).
        Task {
            try? await Task.sleep(for: .seconds(5))
            await computeSizes()
        }
        Task { await refreshCatalog() }
        Task { await refreshPopularity() }
        Task { await refreshOutdated(confirmWithBrew: true) }
        Task { await refreshTaps() }
        Task { await refreshServices() }
        Task {
            while isCatalogLoading { try? await Task.sleep(for: .milliseconds(200)) }
            await scanAdoptable()
        }
    }

    // MARK: Last-known state

    private func restore(_ s: StateSnapshot) {
        installed = Dictionary(s.installed.map { ($0.id, $0) }) { a, _ in a }
        outdated = Dictionary(s.outdated.map { ($0.id, $0) }) { a, _ in a }
        outdatedCheckedAt = s.outdatedCheckedAt
        sizes = s.sizes
        services = s.services
        taps = s.taps
        updateBadges()
    }

    /// Debounced: many state changes arrive together after an operation.
    private func scheduleStateSave() {
        guard !AppInfo.isDemo, phase == .ready else { return }
        stateSaveTask?.cancel()
        stateSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let snapshot = StateSnapshot(installed: Array(installed.values), outdated: Array(outdated.values),
                                         outdatedCheckedAt: outdatedCheckedAt, sizes: sizes,
                                         services: services, taps: taps, env: env)
            Task.detached(priority: .background) { snapshot.save() }
        }
    }

    private func configure(env: BrewEnvironment) {
        self.env = env
        let runner = BrewRunner(env: env) { Self.extraEnvironment() }
        self.runner = runner
        operations.configure(runner: runner)
        updater.detectChannel(env: env)
        watcher = FSEventsWatcher(paths: [env.cellar, env.caskroom, env.pinnedDir, env.prefix.appending(path: "var/homebrew")]) { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
    }

    /// Proxy and mirror (Settings → Network), then extra variables from Settings → Homebrew
    /// ("KEY=value" per line), which win if they set the same name.
    nonisolated static func extraEnvironment() -> [String: String] {
        let text = UserDefaults.standard.string(forKey: "extraEnvironment") ?? ""
        var out = NetworkSettings.environment()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { out[parts[0]] = parts[1] }
        }
        return out
    }

    func retryLocating() async {
        phase = .locating
        BrewLocator.invalidateCache()
        await start()
    }

    // MARK: Catalog

    private func apply(_ catalog: Catalog, firstSeen: [String: Date]) async {
        let t = Perf.begin("catalog.index")
        let cats = categories
        let overrides = userData.categoryOverrides
        let pop = popularity
        let built = await Task.detached(priority: .userInitiated) {
            let pkgs = catalog.packages
            var index: [String: Int] = [:]
            index.reserveCapacity(pkgs.count)
            var formulae = 0
            for (i, p) in pkgs.enumerated() {
                index[p.id] = i
                if p.kind == .formula { formulae += 1 }
            }
            let assignments = pkgs.map { cats.category(for: $0, overrides: overrides) }
            var counts: [PackageCategory: Int] = [:]
            for a in assignments { counts[a.category, default: 0] += 1 }
            let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
            let recent = firstSeen.compactMap { id, d -> (index: Int, date: Date)? in
                guard d > cutoff, let i = index[id] else { return nil }
                return (i, d)
            }.sorted { $0.date > $1.date }
            let rankings = Self.rankings(packages: pkgs, popularity: pop)
            return (pkgs, index, SearchIndex(packages: pkgs), DependencyGraph(packages: pkgs, aliases: catalog.formulaAliases),
                    assignments, counts, formulae, recent, rankings)
        }.value
        packages = built.0
        indexByID = built.1
        searchIndex = built.2
        graph = built.3
        categoryOf = built.4.map(\.category)
        categoryIsAuto = built.4.map(\.isAuto)
        categoryCounts = built.5
        formulaCount = built.6
        caskCount = built.0.count - built.6
        recentPackages = built.7
        newThisWeekCount = built.7.filter { $0.date > Date.now.addingTimeInterval(-7 * 86_400) }.count
        applyRankings(built.8)
        formulaAliases = catalog.formulaAliases
        catalogGeneratedAt = catalog.generatedAt
        catalogLoadedAt = .now
        self.firstSeen = firstSeen
        if catalog.sourceDescription != "hot" { hasFullCatalog = true }
        Perf.end(t)
    }

    struct Rankings: Sendable {
        var byIndex: [Int]
        var popular: [Int]
        var trending: [(index: Int, trend: Double)]
        /// Every catalog index in order, for each analytics sort; lists filter these instead of sorting.
        var orders: [SortOrder: [Int]]
    }

    nonisolated static func rankings(packages: [Package], popularity: Popularity) -> Rankings {
        let byIndex = packages.map { popularity.installs30[$0.id] ?? 0 }
        func order(_ key: [Double]) -> [Int] {
            key.indices.sorted { key[$0] != key[$1] ? key[$0] > key[$1] : $0 < $1 }
        }
        let k30 = byIndex.map(Double.init)
        let k90 = packages.map { Double(popularity.installs90[$0.id] ?? 0) }
        let k365 = packages.map { Double(popularity.installs365[$0.id] ?? 0) }
        // Growth weighted by volume, so a jump from 10 to 30 installs doesn't outrank real momentum.
        let trendKey: [Double] = packages.indices.map { i in
            guard let t = popularity.trend(packages[i].id) else { return -.infinity }
            return t * log10(Double(max(byIndex[i], 1)))
        }
        let o30 = order(k30)
        let oTrend = order(trendKey)
        let popular = Array(o30.prefix { byIndex[$0] > 0 }.prefix(2000))
        let trending = oTrend.lazy
            .filter { trendKey[$0] > 0 && !packages[$0].isDeprecated && !packages[$0].isDisabled }
            .prefix(200)
            .map { (index: $0, trend: popularity.trend(packages[$0].id) ?? 0) }
        return Rankings(byIndex: byIndex, popular: popular, trending: Array(trending),
                        orders: [.popularity: o30, .installs90: order(k90), .installs365: order(k365), .trending: oTrend])
    }

    func refreshCatalog(force: Bool = false) async {
        guard let env, !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        do {
            if let result = try await catalogStore.refreshIfNeeded(env: env, force: force || packages.isEmpty) {
                await apply(result.catalog, firstSeen: result.firstSeen)
                await rescanInstalled()
                recomputeOutdatedLocally()
            }
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
            log.error("catalog refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Recomputes popularity orderings off the main thread when analytics change.
    private func rebuildRankings() {
        let pkgs = packages, pop = popularity
        Task {
            let r = await Task.detached(priority: .utility) { Self.rankings(packages: pkgs, popularity: pop) }.value
            guard pkgs.count == packages.count else { return }
            applyRankings(r)
        }
    }

    private func applyRankings(_ r: Rankings) {
        popularityByIndex = r.byIndex
        popularRanking = r.popular
        trendingRanking = r.trending
        sortOrders = r.orders
        dataVersion &+= 1
    }

    func refreshPopularity() async {
        guard UserDefaults.standard.object(forKey: "fetchAnalytics") as? Bool ?? true else { return }
        if let p = await popularityStore.refresh() { popularity = p }
    }

    /// Re-applies category assignments after the user overrides one.
    func reassignCategories() {
        let overrides = userData.categoryOverrides
        let assignments = packages.map { categories.category(for: $0, overrides: overrides) }
        categoryOf = assignments.map(\.category)
        categoryIsAuto = assignments.map(\.isAuto)
        var counts: [PackageCategory: Int] = [:]
        for c in categoryOf { counts[c, default: 0] += 1 }
        categoryCounts = counts
    }

    // MARK: Lookups

    func package(_ id: String) -> Package? { indexByID[id].map { packages[$0] } }

    func package(named name: String, kind: PackageKind? = nil) -> Package? {
        if let kind { return package(Package.id(kind, name)) ?? package(Package.id(kind, formulaAliases[name] ?? name)) }
        return package(Package.id(.formula, name)) ?? package(Package.id(.cask, name))
            ?? formulaAliases[name].flatMap { package(Package.id(.formula, $0)) }
    }

    func isInstalled(_ id: String) -> Bool { installed[id] != nil }
    func isOutdated(_ id: String) -> Bool { visibleOutdated[id] != nil }
    func isPinned(_ id: String) -> Bool { installed[id]?.isPinned ?? false }
    func installs30(_ id: String) -> Int { popularity.installs30[id] ?? 0 }
    func category(of p: Package) -> PackageCategory { indexByID[p.id].map { categoryOf[$0] } ?? CategoryStore.heuristic(p) }

    /// Synthesizes a package for something installed that the catalog doesn't know (e.g. a removed formula).
    func packageOrStub(_ inst: InstalledPackage) -> Package {
        package(inst.id) ?? Package(kind: inst.kind, token: inst.token, fullName: inst.token, displayName: inst.token,
                                    desc: String(localized: "Not in the current catalog"), homepage: "",
                                    version: inst.currentVersion, tap: inst.tap ?? "unknown")
    }

    var installedPackages: [Package] { installed.values.map(packageOrStub) }
    var installedFormulaNames: Set<String> { Set(installed.values.filter { $0.kind == .formula }.map(\.token)) }
    var requestedFormulaNames: Set<String> { Set(installed.values.filter { $0.kind == .formula && $0.installedOnRequest }.map(\.token)) }

    private func recomputeVisibleOutdated() {
        let skipped = userData.skipped
        let visible = skipped.isEmpty ? outdated : outdated.filter { skipped[$0.key] != $0.value.available }
        if visible != visibleOutdated { visibleOutdated = visible }
    }

    /// Installed packages Homebrew has deprecated or disabled (for the Updates page).
    var deprecatedInstalled: [Package] {
        installed.keys.compactMap { package($0) }.filter { $0.isDeprecated || $0.isDisabled }.sorted { $0.token < $1.token }
    }

    var upgradableCount: Int { visibleOutdated.values.filter { !$0.pinned }.count }

    var appPathByID: [String: String] {
        var out: [String: String] = [:]
        for i in installed.values where i.kind == .cask { if let p = i.appPaths.first { out[i.id] = p } }
        return out
    }

    // MARK: Installed state

    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await rescanInstalled()
            recomputeOutdatedLocally()
        }
    }

    func rescanInstalled() async {
        guard let env, !AppInfo.isDemo else { return }
        let t = Perf.begin("installed.scan")
        let apps = Dictionary(packages.filter { $0.kind == .cask && !$0.appNames.isEmpty }.map { ($0.token, $0.appNames) }) { a, _ in a }
        let list = await Task.detached(priority: .userInitiated) {
            InstalledScanner.scan(env: env, catalogApps: apps)
        }.value
        installed = Dictionary(list.map { ($0.id, $0) }) { a, _ in a }
        Perf.end(t)
        recomputeOutdatedLocally()
        saveHotSnapshot()
    }

    /// Keeps the launch-time hot snapshot in sync, once the full catalog is in memory.
    private func saveHotSnapshot() {
        guard packages.count > 1000, !installed.isEmpty else { return }
        let hot = installed.keys.compactMap { package($0) }
        Task.detached(priority: .background) { [catalogStore] in await catalogStore.saveHot(hot) }
    }

    /// Computes disk usage in the background: every installed package, or just `ids`.
    func computeSizes(only ids: Set<String>? = nil) async {
        guard let env, !isComputingSizes else { return }
        isComputingSizes = true
        defer { isComputingSizes = false }
        let items = installed.values.filter { ids?.contains($0.id) ?? true }.map { ($0.id, $0.kind, $0.token, $0.appPaths) }
        let result = await Task.detached(priority: .utility) { () -> [String: Int64] in
            var out: [String: Int64] = [:]
            for (id, kind, token, apps) in items {
                if kind == .formula {
                    out[id] = Paths.diskSize(env.cellar.appending(path: token))
                } else {
                    out[id] = apps.reduce(Int64(0)) { $0 + Paths.diskSize(URL(fileURLWithPath: $1)) }
                        + Paths.diskSize(env.caskroom.appending(path: token))
                }
            }
            return out
        }.value
        if ids == nil {
            sizes = result.filter { installed[$0.key] != nil }
        } else {
            var merged = sizes
            for id in ids ?? [] { merged[id] = result[id] }
            sizes = merged
        }
    }

    var totalInstalledSize: Int64 { sizes.values.reduce(0, +) }

    // MARK: Outdated

    /// Instant estimate from catalog versions vs. what's on disk.
    func recomputeOutdatedLocally() {
        guard !packages.isEmpty else { return }
        let greedy = UserDefaults.standard.bool(forKey: "greedyCasks")
        var result: [String: OutdatedInfo] = [:]
        for inst in installed.values {
            guard let p = package(inst.id), !p.version.isEmpty else { continue }
            let have = inst.currentVersion
            let want = p.fullVersion
            if inst.kind == .formula {
                guard BrewVersion(have) < BrewVersion(want) else { continue }
            } else {
                if p.version == "latest" || (p.autoUpdates && !greedy) { continue }
                guard have != p.version, BrewVersion(have) < BrewVersion(p.version) else { continue }
            }
            result[inst.id] = OutdatedInfo(id: inst.id, kind: inst.kind, token: inst.token, installed: have,
                                           available: inst.kind == .formula ? want : p.version, pinned: inst.isPinned)
        }
        // Once brew has answered, its list is authoritative: the local diff may only drop entries
        // that were upgraded or uninstalled since (e.g. in Terminal), never add or reshuffle.
        if outdatedCheckedAt != nil {
            result = outdated.filter { id, info in installed[id].map { $0.currentVersion == info.installed || result[id] != nil } ?? false }
        }
        if result != outdated { outdated = result }
        updateBadges()
    }

    /// Confirms with `brew outdated --json=v2`, which is authoritative.
    func refreshOutdated(confirmWithBrew: Bool) async {
        recomputeOutdatedLocally()
        guard confirmWithBrew, let runner, !isCheckingOutdated else { return }
        isCheckingOutdated = true
        defer { isCheckingOutdated = false }
        var args = ["outdated", "--json=v2"]
        if UserDefaults.standard.bool(forKey: "greedyCasks") { args.append("--greedy") }
        guard let obj = await runner.json(args) as? [String: Any] else { return }
        var result: [String: OutdatedInfo] = [:]
        for (key, kind) in [("formulae", PackageKind.formula), ("casks", .cask)] {
            for item in obj[key] as? [[String: Any]] ?? [] {
                let name = (item["name"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
                let id = Package.id(kind, name)
                result[id] = OutdatedInfo(
                    id: id, kind: kind, token: name,
                    installed: (item["installed_versions"] as? [String])?.last ?? "",
                    available: item["current_version"] as? String ?? "",
                    pinned: item["pinned"] as? Bool ?? false)
            }
        }
        if Set(result.keys) != Set(outdated.keys) {
            log.info("outdated: disk estimate \(self.outdated.count) vs brew \(result.count); trusting brew")
        }
        outdated = result
        outdatedCheckedAt = .now
        updateBadges()
    }

    func updateBadges() {
        let n = upgradableCount
        let showDock = UserDefaults.standard.object(forKey: "dockBadge") as? Bool ?? true
        NSApp?.dockTile.badgeLabel = (showDock && n > 0) ? "\(n)" : nil
    }

    // MARK: Services & taps

    func refreshServices() async {
        guard let runner else { return }
        services = BrewService.parse(await runner.json(["services", "list", "--json"]))
    }

    func refreshTaps() async {
        guard let runner else { return }
        taps = BrewTap.parse(await runner.json(["tap-info", "--json", "--installed"]))
    }

    // MARK: Search & filtering

    struct ListFilter: Equatable {
        var kind: PackageKind?
        var installedOnly = false
        var notInstalledOnly = false
        var outdatedOnly = false
        var pinnedOnly = false
        var deprecatedOnly = false
        var disabledOnly = false
        var tap: String?
        var category: PackageCategory?
        var tag: String?
        var favouritesOnly = false
        var leavesOnly = false
        var newOnly = false
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        // "popularity" is the stored value of the 30-day order from earlier versions.
        case name, popularity, installs90, installs365, trending, installDate, size, lastUpdated
        var id: String { rawValue }

        /// Menu label.
        var label: String {
            switch self {
            case .name: String(localized: "Name")
            case .popularity: String(localized: "Most Installed — 30 Days")
            case .installs90: String(localized: "Most Installed — 90 Days")
            case .installs365: String(localized: "Most Installed — Year")
            case .trending: String(localized: "Trending")
            case .installDate: String(localized: "Install Date")
            case .size: String(localized: "Size")
            case .lastUpdated: String(localized: "Recently Added")
            }
        }

        /// Compact label for the list header.
        var shortLabel: String {
            switch self {
            case .popularity: String(localized: "Installs · 30d")
            case .installs90: String(localized: "Installs · 90d")
            case .installs365: String(localized: "Installs · 1y")
            default: label
            }
        }

        /// Orders that rank by Homebrew's install analytics.
        var isAnalytics: Bool { [.popularity, .installs90, .installs365, .trending].contains(self) }

        /// Separators in the sort menu go before these.
        var startsGroup: Bool { self == .popularity || self == .installDate }
    }

    /// The list sort, type and filters live here (not in view state) so Discover's "See all" can
    /// open a list already ranked the way the shelf was. Persisted across launches.
    var listSort: SortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "browser.sort") ?? "") ?? .name {
        didSet { if !AppInfo.isDemo { UserDefaults.standard.set(listSort.rawValue, forKey: "browser.sort") } }
    }
    var listKind: PackageKind? = PackageKind(rawValue: UserDefaults.standard.string(forKey: "browser.kind") ?? "") {
        didSet { if !AppInfo.isDemo { UserDefaults.standard.set(listKind?.rawValue ?? "", forKey: "browser.kind") } }
    }
    var listFilters: Set<String> = Set((UserDefaults.standard.string(forKey: "browser.filters") ?? "").split(separator: ",").map(String.init)) {
        didSet { if !AppInfo.isDemo { UserDefaults.standard.set(listFilters.sorted().joined(separator: ","), forKey: "browser.filters") } }
    }

    /// Opens a full list ranked like the Discover shelf it came from, with nothing else narrowing it.
    func showAll(_ section: SidebarItem, sort: SortOrder) {
        searchText = ""
        listKind = nil
        listFilters = []
        listSort = sort
        sidebar = section
    }

    /// The number a row shows for the current sort ("161k", "↑ 64%", "54 MB"…), or nil.
    func metric(for p: Package, sort: SortOrder) -> String? {
        switch sort {
        case .name: return nil
        case .popularity: return installCount(popularity.installs30[p.id])
        case .installs90: return installCount(popularity.installs90[p.id])
        case .installs365: return installCount(popularity.installs365[p.id])
        case .trending: return popularity.trend(p.id).map { $0 >= 0 ? "↑ \(Int($0 * 100))%" : "↓ \(Int(-$0 * 100))%" } ?? "—"
        case .installDate: return installed[p.id]?.installedAt?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        case .size: return sizes[p.id].map(\.byteString)
        case .lastUpdated:
            guard let d = firstSeen[p.id], d > .distantPast else { return nil }
            return d.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
    }

    private func installCount(_ n: Int?) -> String {
        guard let n, n > 0 else { return "—" }
        return n.compact
    }

    /// The package list for any screen: search text (with `is:`/`tag:`… filters) + filter + sort.
    /// Works on catalog indices with precomputed keys; ~1 ms for the full catalog in Release.
    func list(query raw: String, filter base: ListFilter, sort: SortOrder) -> PackageList {
        let t = Perf.begin("list")
        defer { Perf.end(t) }
        let q = SearchQuery(raw)
        var f = base
        if let k = q.kind { f.kind = k }
        if q.isInstalled { f.installedOnly = true }
        if q.isOutdated { f.outdatedOnly = true }
        if q.isPinned { f.pinnedOnly = true }
        if q.isDeprecated { f.deprecatedOnly = true }

        let tagSets: [Set<String>] = (q.tags + (f.tag.map { [$0] } ?? [])).map { Set(userData.tag(named: $0)?.packageIDs ?? []) }
        let catFilters = q.categories.compactMap { slug in PackageCategory.allCases.first { $0.slug.hasPrefix(slug) } }
        // Read every observable property once: each access inside a 16k-iteration loop would go
        // through observation tracking.
        let outdatedNow = visibleOutdated
        let installedNow = installed
        let favourites = userData.favourites
        let pkgs = packages
        let byID = indexByID
        let categories = categoryOf
        let popByIndex = popularityByIndex
        let pop = popularity
        let sizesNow = sizes
        let seen = firstSeen
        let index = searchIndex
        let orders = sortOrders

        // Narrow candidates cheaply first: installed-only screens start from ~200 packages, not 16k.
        var candidates: [Int]
        if f.installedOnly || f.leavesOnly || f.outdatedOnly || f.pinnedOnly {
            candidates = installedNow.keys.compactMap { byID[$0] }.sorted()
        } else if f.favouritesOnly {
            candidates = favourites.compactMap { byID[$0] }.sorted()
        } else if f.newOnly {
            let weekAgo = Date.now.addingTimeInterval(-30 * 86_400)
            candidates = recentPackages.filter { $0.date > weekAgo }.map(\.index).sorted()
        } else if !tagSets.isEmpty {
            candidates = tagSets[0].compactMap { byID[$0] }.sorted()
        } else {
            candidates = Array(pkgs.indices)
        }
        let leaves = f.leavesOnly ? Set(graph.leaves(installed: installedFormulaNames).map { Package.id(.formula, $0) }) : []

        func keep(_ i: Int) -> Bool {
            let p = pkgs[i]
            if let k = f.kind, p.kind != k { return false }
            if f.installedOnly && installedNow[p.id] == nil { return false }
            if f.notInstalledOnly && installedNow[p.id] != nil { return false }
            if f.outdatedOnly && outdatedNow[p.id] == nil { return false }
            if f.pinnedOnly && !(installedNow[p.id]?.isPinned ?? false) { return false }
            if f.deprecatedOnly && !p.isDeprecated { return false }
            if f.disabledOnly && !p.isDisabled { return false }
            if let tap = f.tap, p.tap != tap { return false }
            if !q.taps.isEmpty && !q.taps.contains(where: { p.tap.lowercased().hasPrefix($0) }) { return false }
            if let c = f.category, categories[i] != c { return false }
            if !catFilters.isEmpty && !catFilters.contains(categories[i]) { return false }
            if !tagSets.allSatisfy({ $0.contains(p.id) }) { return false }
            if f.favouritesOnly && !favourites.contains(p.id) { return false }
            if f.leavesOnly && !leaves.contains(p.id) { return false }
            return true
        }

        var indices: [Int]
        if q.text.isEmpty {
            indices = candidates.filter(keep)
        } else {
            // Relevance order while typing.
            let hits = index.searchWords(q.text, limit: 2000, popularity: popByIndex)
            let allowed = candidates.count == pkgs.count ? nil : Set(candidates)
            let matched = hits.lazy.map(\.index).filter { (allowed?.contains($0) ?? true) && keep($0) }
            // Name order means "best match" while typing; any other chosen order is applied to the hits.
            if sort == .name { return PackageList(catalog: pkgs, order: Array(matched)) }
            indices = Array(matched)
        }

        // The catalog is stored in name order, so .name needs no sort. Every other order builds one
        // key per row, then sorts descending; ties fall back to name order.
        if let order = orders[sort], order.count == pkgs.count {
            // Analytics orders are precomputed: keep the ranked indices that passed the filters.
            if indices.count == pkgs.count {
                indices = order
            } else {
                var included = [Bool](repeating: false, count: pkgs.count)
                for i in indices { included[i] = true }
                indices = order.filter { included[$0] }
            }
        } else if sort != .name {
            let keys: [Double] = indices.map { i in
                let id = pkgs[i].id
                switch sort {
                case .name: return 0
                case .popularity: return Double(i < popByIndex.count ? popByIndex[i] : 0)
                case .installs90: return Double(pop.installs90[id] ?? 0)
                case .installs365: return Double(pop.installs365[id] ?? 0)
                case .trending:
                    // Growth weighted by volume, as on Discover; packages without enough data last.
                    guard let t = pop.trend(id) else { return -.infinity }
                    return t * log10(Double(max(pop.installs30[id] ?? 1, 1)))
                case .installDate: return installedNow[id]?.installedAt?.timeIntervalSince1970 ?? -.infinity
                case .size: return Double(sizesNow[id] ?? 0)
                case .lastUpdated: return seen[id].map { $0.timeIntervalSince1970 } ?? -.infinity
                }
            }
            let order = keys.indices.sorted { keys[$0] != keys[$1] ? keys[$0] > keys[$1] : $0 < $1 }
            indices = order.map { indices[$0] }
        }
        // Installed packages the catalog doesn't know (removed formulae, uncatalogued taps).
        var extra: [Package] = []
        if f.installedOnly {
            for inst in installedNow.values where byID[inst.id] == nil {
                if let k = f.kind, inst.kind != k { continue }
                extra.append(packageOrStub(inst))
            }
        }
        return PackageList(catalog: pkgs, order: indices, extra: extra)
    }

    // MARK: Discover data

    func trending(limit: Int = 12) -> [(Package, Double)] {
        trendingRanking.prefix(limit).map { (packages[$0.index], $0.trend) }
    }

    func mostPopular(limit: Int = 12, kind: PackageKind? = nil) -> [Package] {
        popularRanking.lazy.map { self.packages[$0] }.filter { kind == nil || $0.kind == kind }.prefix(limit).map { $0 }
    }

    func newPackages(within days: Double = 30, limit: Int = 24) -> [(Package, Date)] {
        let cutoff = Date.now.addingTimeInterval(-days * 86_400)
        return recentPackages.lazy.filter { $0.date > cutoff }.prefix(limit).map { (packages[$0.index], $0.date) }
    }

    var recentlyUpdatedInstalled: [OutdatedInfo] {
        visibleOutdated.values.sorted { $0.token < $1.token }
    }

    // MARK: Navigation history

    private func recordNavigation(_ entry: NavEntry) {
        guard !isNavigating else { return }
        if navIndex < navStack.count - 1 { navStack.removeSubrange((navIndex + 1)...) }
        if navStack.last != entry { navStack.append(entry); navIndex = navStack.count - 1 }
    }

    var canGoBack: Bool { navIndex > 0 }
    var canGoForward: Bool { navIndex < navStack.count - 1 }

    func goBack() { guard canGoBack else { return }; navIndex -= 1; restoreNav() }
    func goForward() { guard canGoForward else { return }; navIndex += 1; restoreNav() }

    private func restoreNav() {
        isNavigating = true
        defer { isNavigating = false }
        switch navStack[navIndex] {
        case .section(let s): sidebar = s
        case .package(let id): selectedPackageID = id
        }
    }

    /// Opens a package from anywhere (palette, menu bar, dependency chip).
    func reveal(_ id: String) {
        if !isListScreen(sidebar) {
            sidebar = isInstalled(id) ? .installed : .allPackages
        }
        selectedPackageID = id
        NSApp.activate()
    }

    func isListScreen(_ s: SidebarItem) -> Bool {
        switch s {
        case .installed, .allPackages, .favourites, .leaves, .newPackages, .category, .tag: true
        default: false
        }
    }

    // MARK: Toasts

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isError: Bool
    }

    func toast(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toasts.append(t)
        Task {
            try? await Task.sleep(for: .seconds(error ? 6 : 3.5))
            toasts.removeAll { $0.id == t.id }
        }
    }

    // MARK: Operation results

    private func operationFinished(_ op: BrewOperation) {
        if op.isMutating {
            userData.record(op)
            Task {
                await rescanInstalled()
                if op.args.first == "update" { await refreshCatalog() }
                await refreshOutdated(confirmWithBrew: true)
                if op.args.first == "services" { await refreshServices() }
                if ["tap", "untap", "trust", "untrust"].contains(op.args.first ?? "") { await refreshTaps() }
                if op.args.contains("--cask") { await scanAdoptable() }
                if !sizes.isEmpty { await computeSizes(only: Set(op.packages.flatMap { [Package.id(.formula, $0), Package.id(.cask, $0)] })) }
            }
        }
        // Close the drawer by itself once everything has finished cleanly. Failures, warnings and
        // notices keep it open so they're never hidden.
        let clean = !op.log.contains { $0.kind == .warning || $0.kind == .error } && op.notices.isEmpty
        if op.state == .succeeded && clean && showActivity {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                let failed = operations.operations.contains { if case .failed = $0.state { $0.finishedAt.map { $0 > .now.addingTimeInterval(-30) } ?? false } else { false } }
                if !operations.hasActive && !failed { showActivity = false }
            }
        }
        switch op.state {
        case .succeeded where op.isMutating: toast(String(localized: "\(op.title) finished"))
        case .failed:
            // Errors are never only a toast: the Activity panel opens on the failed operation.
            toast(String(localized: "\(op.title) failed"), error: true)
            showActivity = true
        default: break
        }
    }

    // MARK: Smart search

    /// The last plain-language search, so the list can show how it was interpreted.
    struct SmartContext: Equatable {
        var request: String
        var query: SmartQuery
    }
    var smartContext: SmartContext?
    private(set) var isSmartSearching = false

    /// Turns a plain-language request into filters (on-device model, or keywords), then shows the
    /// results in All Packages with the interpretation in a banner.
    func smartSearch(_ request: String) async {
        let text = request.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSmartSearching else { return }
        isSmartSearching = true
        defer { isSmartSearching = false }
        let q = await SmartSearch.interpret(text)
        smartContext = SmartContext(request: text, query: q)
        listKind = nil
        listFilters = []
        searchText = q.queryString
        if !isListScreen(sidebar) || sidebar == .installed && !q.installedOnly { sidebar = .allPackages }
    }

    // MARK: Adoption

    func scanAdoptable() async {
        guard !isScanningAdoptable, hasFullCatalog else { return }
        if AppInfo.isDemo { adoptable = DemoData.adoptable; adoptableScannedAt = .now; return }
        isScanningAdoptable = true
        defer { isScanningAdoptable = false }
        let casks = packages.filter { $0.kind == .cask && !$0.appNames.isEmpty }
        let installedCasks = Set(installed.values.filter { $0.kind == .cask }.map(\.token))
        let managed = Set(installed.values.flatMap { $0.appPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } })
        adoptable = await Task.detached(priority: .utility) {
            AdoptionScanner.match(bundles: AdoptionScanner.scanBundles(), casks: casks, installedCasks: installedCasks, managedPaths: managed)
        }.value
        adoptableScannedAt = .now
    }

    func adoptCommands(_ apps: [AdoptableApp]) -> [BrewCommand] {
        apps.map { BrewCommand(String(localized: "Adopt \($0.name)"), ["install", "--cask", "--adopt", $0.token], packages: [$0.token]) }
    }

    var adoptableReady: [AdoptableApp] { adoptable.filter { $0.status == .ready } }

    // MARK: Maintenance

    func runDoctor() async {
        guard let runner, !isRunningDoctor else { return }
        isRunningDoctor = true
        defer { isRunningDoctor = false }
        let r = await runner.output(["doctor"])
        doctorWarnings = MaintenanceParsers.doctor(r.stdout + "\n" + r.stderr)
        doctorRanAt = .now
    }

    /// Always a dry run first (`brew cleanup -n`); nothing is deleted until the user confirms.
    func previewCleanup() async {
        guard let runner, !isPreviewingCleanup else { return }
        isPreviewingCleanup = true
        defer { isPreviewingCleanup = false }
        let r = await runner.output(["cleanup", "-n"] + (cleanupPruneAll ? ["--prune=all"] : []))
        cleanupPreview = MaintenanceParsers.cleanup(r.stdout + "\n" + r.stderr)
    }

    func runCleanup() {
        operations.enqueue(String(localized: "Clean up"), ["cleanup"] + (cleanupPruneAll ? ["--prune=all"] : []))
        showActivity = true
        cleanupPreview = nil
    }

    /// Opens Maintenance and starts the doctor (from the palette or menus).
    func showDoctor() {
        sidebar = .maintenance
        Task { await runDoctor() }
    }

    /// Opens Maintenance with a fresh cleanup preview.
    func showCleanup() {
        sidebar = .maintenance
        Task { await previewCleanup() }
    }

    // MARK: Notices

    /// Brew printed something that needs a decision: ask once per session.
    private func handle(_ notice: OperationNotice) {
        switch notice {
        case .untrustedTaps(let taps):
            let fresh = taps.filter { !promptedTaps.contains($0) }
            guard !fresh.isEmpty, pendingNotice == nil else { return }
            promptedTaps.formUnion(fresh)
            pendingNotice = .untrustedTaps(fresh)
        }
    }

    /// `brew trust --tap`: Homebrew will load everything the tap provides now and in future.
    func trustTaps(_ taps: [String]) {
        guard !taps.isEmpty else { return }
        let title = taps.count == 1 ? String(localized: "Trust tap \(taps[0])") : String(localized: "Trust \(taps.count) taps")
        operations.enqueue(title, ["trust", "--tap"] + taps, packages: taps)
    }

    // MARK: Demo

    private func loadDemo() {
        let demo = DemoData.make()
        Task {
            await apply(demo.catalog, firstSeen: demo.firstSeen)
            installed = Dictionary(demo.installed.map { ($0.id, $0) }) { a, _ in a }
            popularity = demo.popularity
            sizes = demo.sizes
            outdated = demo.outdated
            outdatedCheckedAt = .now.addingTimeInterval(-240)
            services = demo.services
            taps = demo.taps
            env = demo.env
            let runner = MockBrewRunner()
            self.runner = runner
            operations.configure(runner: runner)
            phase = .ready
            adoptable = DemoData.adoptable
            adoptableScannedAt = .now
            updateBadges()
        }
    }
}

/// Requests for sheets that several screens can trigger.
enum SheetRequest: Identifiable, Equatable {
    case install([String])
    case uninstall(String)
    case removeCompletely(String)
    case autoremove
    case addTap
    case graph(String)
    case switchVersion(String)
    case removeOldVersions(String)
    case clearCache(String)
    case whyInstalled(String)
    case brewfileImport(URL)

    var id: String {
        switch self {
        case .install(let ids): "install:" + ids.joined(separator: ",")
        case .uninstall(let id): "uninstall:" + id
        case .removeCompletely(let id): "remove:" + id
        case .autoremove: "autoremove"
        case .addTap: "addTap"
        case .graph(let id): "graph:" + id
        case .switchVersion(let id): "switch:" + id
        case .removeOldVersions(let id): "oldversions:" + id
        case .clearCache(let id): "cache:" + id
        case .whyInstalled(let id): "why:" + id
        case .brewfileImport(let url): "brewfile:" + url.path
        }
    }
}

/// A list of packages as indices into the catalog, so building a 16k-row list never copies
/// 16k package records; rows fetch their package when they're shown.
struct PackageList: RandomAccessCollection, Sendable {
    let catalog: [Package]
    let order: [Int]
    var extra: [Package] = []

    static let empty = PackageList(catalog: [], order: [])

    var startIndex: Int { 0 }
    var endIndex: Int { order.count + extra.count }
    subscript(position: Int) -> Package {
        position < order.count ? catalog[order[position]] : extra[position - order.count]
    }
}
