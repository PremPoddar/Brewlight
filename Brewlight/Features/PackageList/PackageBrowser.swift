import SwiftUI

/// List + detail for Installed, All Packages, a category, a tag, Favourites, Leaves and New.
struct PackageBrowser: View {
    let section: SidebarItem
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var quickLook: String?
    @State private var cache = ListCache()
    /// Rows materialized so far; grows as the user scrolls. SwiftUI builds identity for every
    /// ForEach element even in a lazy stack, so 16k rows at once cost tens of milliseconds.
    @State private var shown = ListCache.pageSize
    @State private var shownGeneration = 0
    @Environment(\.openWindow) private var openWindow

    private var kind: PackageKind? { model.listKind }
    private var sort: AppModel.SortOrder { model.listSort }
    private var extraFilters: Set<String> { model.listFilters }

    var body: some View {
        let shape = ListCache.Shape(query: model.searchText, section: section, kind: kind?.rawValue ?? "", sort: sort.rawValue,
                                    filters: extraFilters.sorted().joined(separator: ","))
        let items = cache.items(for: shape, version: model.dataVersion) {
            model.list(query: shape.query, filter: filter, sort: sort)
        }
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(count: items.count)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                if let ctx = model.smartContext, model.searchText == ctx.query.queryString {
                    SmartSearchBanner(context: ctx)
                        .padding(.horizontal, 24).padding(.top, 8)
                }
                listView(items)
            }
            .frame(minWidth: 380, idealWidth: 480, maxWidth: 560)
            .background(Theme.list)
            .overlay(alignment: .bottom) {
                if selection.count > 1 { BulkActionBar(selection: $selection).padding(16) }
            }

            Rectangle().fill(Theme.separator).frame(width: 1)

            Group {
                if let id = model.selectedPackageID, selection.count <= 1 {
                    PackageDetailView(packageID: id)
                } else if selection.count > 1 {
                    EmptyStateView(symbol: "square.stack", title: String(localized: "\(selection.count) packages selected"),
                                   message: String(localized: "Use the bar below the list to act on all of them."))
                } else {
                    EmptyStateView(symbol: "shippingbox", title: String(localized: "No package selected"),
                                   message: AppInfo.fullTagline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.detail)
        }
        .onChange(of: model.selectedPackageID) { _, new in
            if let new, !selection.contains(new) { selection = [new] }
        }
        .onAppear {
            if let id = model.selectedPackageID { selection = [id] }
            if section == .installed && model.sizes.isEmpty { Task { await model.computeSizes() } }
        }
        .sheet(item: Binding(get: { quickLook.map(QuickLookID.init) }, set: { quickLook = $0?.id })) { q in
            QuickLookSheet(packageID: q.id)
        }
    }

    private var filter: AppModel.ListFilter {
        var f = AppModel.ListFilter()
        f.kind = kind
        switch section {
        case .installed: f.installedOnly = true
        case .favourites: f.favouritesOnly = true
        case .leaves: f.leavesOnly = true; f.installedOnly = true
        case .newPackages: f.newOnly = true
        case .category(let c): f.category = PackageCategory(rawValue: c)
        case .tag(let t): f.tag = t
        default: break
        }
        let x = extraFilters
        if x.contains("installed") { f.installedOnly = true }
        if x.contains("notInstalled") { f.notInstalledOnly = true }
        if x.contains("outdated") { f.outdatedOnly = true }
        if x.contains("pinned") { f.pinnedOnly = true }
        if x.contains("deprecated") { f.deprecatedOnly = true }
        if x.contains("disabled") { f.disabledOnly = true }
        return f
    }

    private var subtitle: String {
        switch section {
        case .installed:
            let size = model.totalInstalledSize
            return size > 0
                ? String(localized: "\(model.installed.count) packages · \(size.byteString) on disk")
                : String(localized: "\(model.installed.count) packages")
        case .leaves: return String(localized: "Installed packages nothing else depends on")
        case .newPackages: return String(localized: "Added to Homebrew in the last 30 days")
        case .category(let c): return PackageCategory(rawValue: c).map { String(localized: "\(model.categoryCounts[$0] ?? 0) packages") } ?? ""
        default: return ""
        }
    }

    private func header(count: Int) -> some View {
        VStack(spacing: 0) {
            ScreenHeader(title: section.title, subtitle: subtitle.isEmpty ? String(localized: "\(count.formatted()) packages") : subtitle, size: 26) {
                Picker(String(localized: "Type"), selection: Binding(
                    get: { model.listKind?.rawValue ?? "" },
                    set: { model.listKind = PackageKind(rawValue: $0) })) {
                    Text(String(localized: "All")).tag("")
                    Text(String(localized: "Formulae")).tag(PackageKind.formula.rawValue)
                    Text(String(localized: "Casks")).tag(PackageKind.cask.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                LazyMenuButton {
                    var entries: [MenuEntry] = []
                    for order in AppModel.SortOrder.allCases {
                        if order.startsGroup { entries.append(.separator) }
                        entries.append(MenuEntry(order.label, isOn: order == sort) { model.listSort = order })
                    }
                    return entries
                } label: {
                    Text(String(localized: "Sort: \(sort.label) ▾"))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Install counts are Homebrew's public analytics (formulae.brew.sh), from users who haven't opted out."))
                Spacer()
                LazyMenuButton {
                    var entries = filterOptions.map { key, label in
                        MenuEntry(label, isOn: extraFilters.contains(key)) {
                            if model.listFilters.contains(key) { model.listFilters.remove(key) } else { model.listFilters.insert(key) }
                        }
                    }
                    if !extraFilters.isEmpty {
                        entries += [.separator, MenuEntry(String(localized: "Clear Filters")) { model.listFilters = [] }]
                    }
                    return entries
                } label: {
                    Label(extraFilters.isEmpty ? String(localized: "Filter") : String(localized: "Filter (\(extraFilters.count))"),
                          systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plain)
                if sort != .name {
                    Text(sort.shortLabel).frame(width: PackageRow.metricWidth, alignment: .trailing).lineLimit(1)
                }
                Text(String(localized: "Version")).frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        }
    }

    private var filterOptions: [(String, String)] {
        [("installed", String(localized: "Installed")), ("notInstalled", String(localized: "Not Installed")),
         ("outdated", String(localized: "Outdated")), ("pinned", String(localized: "Pinned")),
         ("deprecated", String(localized: "Deprecated")), ("disabled", String(localized: "Disabled"))]
    }

    @ViewBuilder
    private func listView(_ items: PackageList) -> some View {
        if items.isEmpty && (model.isCatalogLoading || (section == .installed && model.phase != .ready)) {
            ProgressView(String(localized: "Loading packages…"))
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            emptyState.frame(maxHeight: .infinity)
        } else {
            // A lazy stack of fixed-height rows instead of List: List measures every visible row's
            // height through NSTableView on each update, which dominated click and scroll time.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        let limit = shownGeneration == cache.generation ? shown : ListCache.pageSize
                        ForEach(items.prefix(limit)) { p in
                            PackageRow(package: p, isSelected: selection.contains(p.id), metric: model.metric(for: p, sort: sort))
                                .contentShape(Rectangle())
                                // One handler: a separate double-tap gesture would delay every
                                // single click by the double-click interval.
                                .onTapGesture {
                                    if NSApp.currentEvent?.clickCount == 2 {
                                        openWindow(id: "package", value: p.id)
                                    } else {
                                        click(p.id, in: items)
                                    }
                                }
                                .contextMenu { PackageContextMenu(package: p) }
                                .id(p.id)
                        }
                        if items.count > limit {
                            // Reaching the end loads the next page.
                            ProgressView().controlSize(.small).frame(height: 40)
                                .onAppear {
                                    shownGeneration = cache.generation
                                    shown = limit + ListCache.pageSize
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .scrollContentBackground(.hidden)
                // At most a page of rows is diffed when the query changes; jump back to the top.
                .onChange(of: cache.generation) {
                    if let first = items.first { proxy.scrollTo(first.id, anchor: .top) }
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, in: items, proxy: proxy); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: items, proxy: proxy); return .handled }
                .onKeyPress(.space) {
                    quickLook = model.selectedPackageID
                    return .handled
                }
            }
        }
    }

    /// Click, ⌘-click (toggle) and ⇧-click (range), like a native table.
    private func click(_ id: String, in items: PackageList) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if flags.contains(.shift), let anchor = model.selectedPackageID,
                  let a = items.firstIndex(where: { $0.id == anchor }), let b = items.firstIndex(where: { $0.id == id }) {
            selection = Set(items[min(a, b)...max(a, b)].map(\.id))
            return
        } else {
            selection = [id]
        }
        if selection.count == 1 { model.selectedPackageID = selection.first }
    }

    private func move(_ delta: Int, in items: PackageList, proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let current = model.selectedPackageID.flatMap { id in items.firstIndex { $0.id == id } }
        let next = min(max((current ?? -1) + delta, 0), items.count - 1)
        if next >= shown - 1 {
            shownGeneration = cache.generation
            shown = max(shown, next + ListCache.pageSize)
        }
        let id = items[next].id
        selection = [id]
        model.selectedPackageID = id
        proxy.scrollTo(id)
    }

    @ViewBuilder private var emptyState: some View {
        if !model.searchText.isEmpty {
            EmptyStateView(symbol: "magnifyingglass", title: String(localized: "No results for “\(model.searchText)”"),
                           message: String(localized: "Try a shorter name, or filters like is:installed, type:cask, tag:work."))
        } else {
            switch section {
            case .installed: EmptyStateView(symbol: "shippingbox", title: String(localized: "Nothing installed yet"), message: String(localized: "Find something in Discover or search with ⌘K."))
            case .favourites: EmptyStateView(symbol: "star", title: String(localized: "No favourites"), message: String(localized: "Star a package in its detail view to keep it here."))
            case .tag(let t): EmptyStateView(symbol: "tag", title: String(localized: "Nothing tagged “\(t)”"), message: String(localized: "Add tags from a package's detail view or context menu."))
            case .newPackages: EmptyStateView(symbol: "seal", title: String(localized: "No new packages yet"), message: String(localized: "New packages appear here after Homebrew's index changes."))
            default: EmptyStateView(symbol: "line.3.horizontal.decrease", title: String(localized: "No matching packages"), message: String(localized: "Adjust or clear the filters."))
            }
        }
    }
}

private struct QuickLookID: Identifiable { let id: String }

struct QuickLookSheet: View {
    let packageID: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PackageDetailView(packageID: packageID)
            .frame(width: 640, height: 640)
            .background(Theme.detail)
            .onKeyPress(.space) { dismiss(); return .handled }
            .onKeyPress(.escape) { dismiss(); return .handled }
    }
}

// MARK: Row

struct PackageRow: View {
    let package: Package
    var isSelected = false
    /// The value the list is sorted by (installs, growth, size…), shown in its own column.
    var metric: String?
    static let metricWidth: CGFloat = 92
    @Environment(AppModel.self) private var model

    var body: some View {
        let inst = model.installed[package.id]
        let out = model.visibleOutdated[package.id]
        HStack(spacing: 12) {
            PackageIcon(package: package, size: 32, appPath: inst?.appPaths.first)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(package.token).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    KindBadge(kind: package.kind)
                    if inst?.isPinned == true {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.text3)
                            .accessibilityLabel(String(localized: "Pinned"))
                    }
                    if model.userData.favourites.contains(package.id) {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.accent)
                    }
                    if package.isDeprecated || package.isDisabled {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
                Text(package.desc).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let metric {
                Text(metric)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(metric.hasPrefix("↑") ? Theme.accentText : Theme.text2)
                    .frame(width: Self.metricWidth, alignment: .trailing)
                    .lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if inst != nil {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text3)
                            .accessibilityLabel(String(localized: "Installed"))
                    }
                    Text(inst?.currentVersion ?? package.version)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                if let out {
                    Text("↑ \(out.available)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentText)
                        .accessibilityLabel(String(localized: "Update available: \(out.available)"))
                }
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Theme.accentTint : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("row-\(package.id)")
    }
}

// MARK: Context menu

struct PackageContextMenu: View {
    let package: Package
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let id = package.id
        let inst = model.installed[id]
        if inst == nil {
            Button(String(localized: "Install")) { model.pendingSheet = .install([id]) }
        } else {
            if model.visibleOutdated[id] != nil {
                Button(String(localized: "Upgrade")) { model.upgrade([id]) }.disabled(inst?.isPinned == true)
            }
            if package.kind == .cask, inst?.appPaths.isEmpty == false {
                Button(String(localized: "Open")) { model.open(id) }
            }
            Button(String(localized: "Reinstall")) { model.reinstall(id) }
            Button(String(localized: "Uninstall"), role: .destructive) { model.pendingSheet = .uninstall(id) }
            Button(String(localized: "Remove Completely"), role: .destructive) { model.pendingSheet = .removeCompletely(id) }
            if package.kind == .formula {
                Button(inst?.isPinned == true ? String(localized: "Unpin") : String(localized: "Pin")) { model.pin(id, !(inst?.isPinned ?? false)) }
            }
            Button(String(localized: "Show in Finder")) { model.showInFinder(id) }
        }
        Divider()
        Button(model.userData.favourites.contains(id) ? String(localized: "Remove from Favourites") : String(localized: "Add to Favourites")) {
            model.userData.toggleFavourite(id)
        }
        if !model.userData.tags.isEmpty {
            Menu(String(localized: "Tags")) {
                ForEach(model.userData.tags, id: \.name) { tag in
                    Toggle(tag.name, isOn: Binding(get: { tag.packageIDs.contains(id) }, set: { _ in model.userData.toggle(tag: tag, on: id) }))
                }
            }
        }
        Divider()
        Button(String(localized: "Open in New Window")) { openWindow(id: "package", value: id) }
        if let url = package.homepageURL { Button(String(localized: "Open Homepage")) { NSWorkspace.shared.open(url) } }
        Button(String(localized: "Copy Install Command")) { model.copy(package.installCommand) }
    }
}

// MARK: Bulk actions

struct BulkActionBar: View {
    @Binding var selection: Set<String>
    @Environment(AppModel.self) private var model

    var body: some View {
        let ids = Array(selection)
        let notInstalled = ids.filter { !model.isInstalled($0) }
        let outdated = ids.filter { model.isOutdated($0) }
        HStack(spacing: 10) {
            Text(String(localized: "\(ids.count) selected")).font(.system(size: 12, weight: .semibold))
            Spacer()
            if !notInstalled.isEmpty {
                Button(String(localized: "Install \(notInstalled.count)")) { model.pendingSheet = .install(notInstalled) }
                    .buttonStyle(.glassProminent)
            }
            if !outdated.isEmpty {
                Button(String(localized: "Upgrade \(outdated.count)")) { model.upgrade(outdated) }
                    .buttonStyle(.glass)
            }
            Button(String(localized: "Deselect")) { selection = [] }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Memoizes the package list so redraws (selection, hover, size updates) never rebuild it.
/// A reference type so the lookup can happen in `body` without mutating view state.
final class ListCache {
    struct Shape: Equatable {
        var query: String
        var section: SidebarItem
        var kind: String
        var sort: String
        var filters: String
    }

    static let pageSize = 150
    private var shape: Shape?
    private var version = -1
    private var cached = PackageList.empty
    private(set) var generation = 0

    func items(for shape: Shape, version: Int, compute: () -> PackageList) -> PackageList {
        if shape == self.shape && version == self.version { return cached }
        if shape != self.shape { generation &+= 1 }
        self.shape = shape
        self.version = version
        cached = compute()
        return cached
    }
}

/// How a plain-language search was understood, so it's never a black box.
struct SmartSearchBanner: View {
    let context: AppModel.SmartContext
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text("“\(context.request)”").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(String(localized: "Searching \(context.query.queryString)")).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text2).lineLimit(2)
                Text(context.query.source == .onDeviceModel
                     ? String(localized: "Interpreted on this Mac by Apple Intelligence; edit the search to adjust.")
                     : String(localized: "Interpreted from keywords; edit the search to adjust."))
                    .font(.system(size: 10)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 0)
            Button { model.smartContext = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.text3)
                .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentTint.opacity(0.6)))
    }
}
