import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var category: PackageCategory?

    var body: some View {
        ScrollView {
            // Lazy: shelves below the fold are built only when scrolled to.
            LazyVStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: String(localized: "Discover"),
                                 subtitle: String(localized: "What the Homebrew community is installing this week"))
                    CategoryChips(selection: $category)
                }

                if model.isCatalogLoading || model.popularRanking.isEmpty {
                    analyticsPlaceholder
                } else {
                    trending
                    popular
                }
                fresh
                if !model.recentlyUpdatedInstalled.isEmpty { recentlyUpdated }
                categoryShelves
            }
            .padding(.horizontal, 36)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.list)
        .task { if model.popularity.installs30.isEmpty { await model.refreshPopularity() } }
    }

    // MARK: Shelves

    /// "See all" respects the category chip: all packages, or just that category.
    private var shelfSection: SidebarItem { category.map { .category($0.rawValue) } ?? .allPackages }

    private var trending: some View {
        let items = model.trendingRanking.lazy.filter { category == nil || model.categoryOf[$0.index] == category }
            .prefix(3).map { (model.packages[$0.index], $0.trend) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "Trending")) { model.showAll(shelfSection, sort: .trending) }
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(items), id: \.0.id) { p, trend in
                    TrendingCard(package: p, trend: trend).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var popular: some View {
        let items = model.popularRanking.lazy.filter { category == nil || model.categoryOf[$0] == category }
            .prefix(9).map { model.packages[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: String(localized: "Popular")) { model.showAll(shelfSection, sort: .popularity) }
            ThreeColumns(items: Array(items)) { i, p in PopularRow(rank: i + 1, package: p) }
        }
    }

    private var fresh: some View {
        let items = model.recentPackages.lazy.filter { category == nil || model.categoryOf[$0.index] == category }
            .prefix(8).map { (model.packages[$0.index], $0.date) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "New in Homebrew")) { model.showAll(.newPackages, sort: .lastUpdated) }
            if items.isEmpty {
                Text(String(localized: "New packages show up here after Homebrew's index changes. Brewlight keeps track from now on."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            } else {
                HStack(spacing: 14) {
                    ForEach(Array(items.prefix(4)), id: \.0.id) { p, date in
                        NewCard(package: p, added: date).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var recentlyUpdated: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "Updates for Your Packages")) { model.sidebar = .updates }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.recentlyUpdatedInstalled.prefix(12)) { info in
                        if let p = model.package(info.id) {
                            Button { model.reveal(p.id) } label: {
                                HStack(spacing: 10) {
                                    PackageIcon(package: p, size: 32, appPath: model.installed[p.id]?.appPaths.first)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.token).font(.system(size: 13, weight: .semibold))
                                        Text("\(info.installed) → \(info.available)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.accentText)
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var categoryShelves: some View {
        let cats: [PackageCategory] = category.map { [$0] } ?? [.developerTools, .terminal, .ai, .browsers]
        return ForEach(cats) { cat in
            let items = model.popularRanking.lazy.filter { model.categoryOf[$0] == cat }.prefix(6).map { model.packages[$0] }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: cat.localizedName) { model.showAll(.category(cat.rawValue), sort: .popularity) }
                    ThreeColumns(items: Array(items)) { _, p in PopularRow(rank: nil, package: p) }
                }
            }
        }
    }

    private var analyticsPlaceholder: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(model.isCatalogLoading ? String(localized: "Loading Homebrew's index…")
                 : String(localized: "Loading install statistics from formulae.brew.sh…")).foregroundStyle(Theme.text2)
        }
        .font(.system(size: 13))
    }
}

// MARK: Cards

struct InstallOrOpenButton: View {
    let package: Package
    @Environment(AppModel.self) private var model

    var body: some View {
        let inst = model.installed[package.id]
        if inst == nil {
            RowActionButton(title: String(localized: "Install")) { model.pendingSheet = .install([package.id]) }
                .accessibilityLabel(String(localized: "Install \(package.token)"))
                .help(package.installCommand)
        } else if model.isOutdated(package.id) {
            RowActionButton(title: String(localized: "Upgrade")) { model.upgrade([package.id]) }
        } else if package.kind == .cask && inst?.appPaths.isEmpty == false {
            RowActionButton(title: String(localized: "Open"), prominent: false) { model.open(package.id) }
        } else {
            RowActionButton(title: String(localized: "View"), prominent: false) { model.reveal(package.id) }
        }
    }
}

struct TrendingCard: View {
    let package: Package
    let trend: Double
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                PackageIcon(package: package, size: 56, appPath: model.installed[package.id]?.appPaths.first)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.token).font(.system(size: 17, weight: .semibold)).tracking(-0.3).lineLimit(1)
                    Text(String(localized: "\(package.kind.label) · \(model.installs30(package.id).compact) installs / 30d"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            Text(package.desc).font(.system(size: 13)).foregroundStyle(Theme.text2).lineSpacing(2)
                .lineLimit(2, reservesSpace: true)
            HStack {
                Text(String(localized: "↑ \(Int(trend * 100))% this month"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentText)
                Spacer()
                InstallOrOpenButton(package: package)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card).shadow(color: .black.opacity(0.04), radius: 1, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.separator))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { model.reveal(package.id) }
        .contextMenu { PackageContextMenu(package: package) }
        .accessibilityElement(children: .contain)
    }
}

struct PopularRow: View {
    let rank: Int?
    let package: Package
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                Text("\(rank)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text3).frame(width: 18)
            }
            PackageIcon(package: package, size: 36, appPath: model.installed[package.id]?.appPaths.first)
            VStack(alignment: .leading, spacing: 1) {
                Text(package.token).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(package.desc).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            InstallOrOpenButton(package: package)
        }
        .frame(height: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { model.reveal(package.id) }
        .contextMenu { PackageContextMenu(package: package) }
    }
}

struct NewCard: View {
    let package: Package
    let added: Date
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            PackageIcon(package: package, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(package.token).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(String(localized: "\(package.kind.label) · added \(added.relative)")).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.isInstalled(package.id) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.text3)
            } else {
                RowActionButton(title: String(localized: "Get")) { model.pendingSheet = .install([package.id]) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
        .contentShape(Rectangle())
        .onTapGesture { model.reveal(package.id) }
        .contextMenu { PackageContextMenu(package: package) }
    }
}

/// Row-major columns built from plain stacks (cheaper than LazyVGrid for a handful of items).
struct Columns<Item, Cell: View>: View {
    let items: [Item]
    var count = 3
    var spacing: CGFloat = 28
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        VStack(spacing: spacing == 28 ? 0 : spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: count)), id: \.self) { start in
                HStack(spacing: spacing) {
                    ForEach(start..<start + count, id: \.self) { i in
                        if i < items.count {
                            cell(items[i]).frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

/// Three columns of packages with their position (for ranks).
struct ThreeColumns<Row: View>: View {
    let items: [Package]
    @ViewBuilder let row: (Int, Package) -> Row

    var body: some View {
        Columns(items: Array(items.enumerated()), count: 3) { pair in row(pair.offset, pair.element) }
    }
}

/// Every category as a horizontally scrolling row of chips, busiest first, with ‹ › buttons for
/// mouse users and faded edges that show there's more.
struct CategoryChips: View {
    @Binding var selection: PackageCategory?
    @Environment(AppModel.self) private var model
    @State private var anchor: String? = "all"

    private var ordered: [PackageCategory] {
        PackageCategory.allCases
            .filter { $0 != .other && (model.categoryCounts[$0] ?? 0) > 0 }
            .sorted { (model.categoryCounts[$0] ?? 0) > (model.categoryCounts[$1] ?? 0) }
            + ((model.categoryCounts[.other] ?? 0) > 0 ? [.other] : [])
    }

    var body: some View {
        let cats = ordered
        let ids = ["all"] + cats.map(\.rawValue)
        HStack(spacing: 6) {
            arrow("chevron.left", label: String(localized: "Scroll categories left")) { step(-4, ids) }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    chip(nil, title: String(localized: "All"), count: nil).id("all")
                    ForEach(cats) { c in
                        chip(c, title: c.localizedName, count: model.categoryCounts[c]).id(c.rawValue)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $anchor, anchor: .leading)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                }
            }
            arrow("chevron.right", label: String(localized: "Scroll categories right")) { step(4, ids) }
        }
    }

    private func chip(_ c: PackageCategory?, title: String, count: Int?) -> some View {
        let on = selection == c
        return Button { selection = c } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let count {
                    Text(count.compact).font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(on ? Theme.list.opacity(0.7) : Theme.text3)
                }
            }
            .foregroundStyle(on ? Theme.list : Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(on ? Theme.text : Theme.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.chip))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int, _ ids: [String]) {
        let current = anchor.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        withAnimation(.easeOut(duration: 0.2)) { anchor = ids[next] }
    }
}
