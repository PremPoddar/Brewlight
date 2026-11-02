import SwiftUI
import UniformTypeIdentifiers

/// The window's root. Its body reads only `phase`; everything that changes often (section, palette,
/// activity, sheets) is read by small child views so a change re-renders just that part, and the
/// toolbar is never rebuilt by unrelated state.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        // GeometryReader takes the size it's offered without asking its content how big it wants
        // to be, so AppKit's window-size queries no longer lay out the entire tree each time.
        GeometryReader { geo in
            root.frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    private var root: some View {
        Group {
            if model.phase == .missingBrew {
                OnboardingView()
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
                } detail: {
                    DetailArea()
                        .toolbar { MainToolbar() }
                        .toolbar(removing: .title)
                }
                .background(Theme.ambient(dark: scheme == .dark).ignoresSafeArea())
            }
        }
        .foregroundStyle(Theme.text)
        .overlay { PaletteOverlay() }
        .overlay(alignment: .bottom) { ToastStack() }
        .overlay(alignment: .bottomTrailing) { PerfOverlay() }
        .modifier(SheetHost())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.sidebar = .brewfile
                model.pendingSheet = .brewfileImport(url)
            }
        }
        return true
    }
}

/// The current section plus the activity drawer.
private struct DetailArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            SectionContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.showActivity {
                ActivityDrawer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.2), value: model.showActivity)
    }
}

private struct SectionContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sidebar {
        case .discover: DiscoverView()
        case .updates: UpdatesView()
        case .adopt: AdoptView()
        case .services: ServicesView()
        case .taps: TapsView()
        case .categories: CategoriesView()
        case .history: HistoryView()
        case .maintenance: MaintenanceView()
        case .brewfile: BrewfileView()
        default: PackageBrowser(section: model.sidebar)
        }
    }
}

private struct PaletteOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.showPalette {
                CommandPalette().transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.showPalette)
    }
}

private struct PerfOverlay: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.showPerfHUD { PerfHUD().padding(16) }
    }
}

private struct SheetHost: ViewModifier {
    @Environment(AppModel.self) private var model

    private var noticeTitle: String {
        switch model.pendingNotice {
        case .untrustedTaps(let taps)?:
            taps.count == 1 ? String(localized: "Trust the tap “\(taps[0])”?") : String(localized: "Trust \(taps.count) taps?")
        case nil: ""
        }
    }
    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(item: $model.pendingSheet) { SheetRouter(request: $0) }
            .alert(noticeTitle, isPresented: Binding(get: { model.pendingNotice != nil }, set: { if !$0 { model.pendingNotice = nil } }),
                   presenting: model.pendingNotice) { notice in
                switch notice {
                case .untrustedTaps(let taps):
                    Button(taps.count == 1 ? String(localized: "Trust \(taps[0])") : String(localized: "Trust \(taps.count) Taps")) {
                        model.trustTaps(taps)
                    }
                    Button(taps.count == 1 ? String(localized: "Untap") : String(localized: "Untap All"), role: .destructive) {
                        for t in taps { model.removeTap(t) }
                    }
                    Button(String(localized: "Learn More")) { NSWorkspace.shared.open(AppModel.tapTrustDocs) }
                    Button(String(localized: "Not Now"), role: .cancel) {}
                }
            } message: { notice in
                switch notice {
                case .untrustedTaps(let taps):
                    Text(String(localized: "Homebrew won't load formulae, casks or commands from \(taps.joined(separator: ", ")) until you trust it. Trusting a tap lets it run code on your Mac whenever you install from it, now and in future. Only trust taps whose authors you trust.\n\nRuns: brew trust --tap \(taps.joined(separator: " "))\nYou can change this later on the Taps page."))
                }
            }
    }
}

// MARK: Sidebar

/// Sidebar from the design: 32 pt rows, rounded amber selection, count pills. Plain stacks instead of
/// a sidebar List, which re-rendered its whole outline view on every selection change.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var newTagName = ""
    @State private var showNewTag = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView { rows }.scrollIndicators(.never)
            StatusCard()
        }
        .alert(String(localized: "New Tag"), isPresented: $showNewTag) {
            TextField(String(localized: "Name"), text: $newTagName)
            Button(String(localized: "Create")) {
                let color = TagPalette.colors[model.userData.tags.count % TagPalette.colors.count]
                model.userData.createTag(newTagName, colorHex: color)
                newTagName = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) { newTagName = "" }
        }
    }

    private var rows: some View {
                VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name).font(.system(size: 17, weight: .bold)).tracking(-0.3)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
                header(String(localized: "Library"))
                SidebarRow(item: .discover)
                SidebarRow(item: .installed, count: model.installed.count)
                SidebarRow(item: .updates, count: model.upgradableCount, hot: true)
                SidebarRow(item: .adopt, count: model.adoptable.filter { $0.status != .appStore }.count)
                SidebarRow(item: .services, count: model.services.filter(\.isRunning).count)
                SidebarRow(item: .taps, count: model.taps.count)
                header(String(localized: "Browse"))
                SidebarRow(item: .allPackages)
                SidebarRow(item: .categories)
                SidebarRow(item: .newPackages, count: model.newThisWeekCount)
                SidebarRow(item: .favourites, count: model.userData.favourites.count)
                SidebarRow(item: .leaves)
                header(String(localized: "Tags"))
                ForEach(model.userData.tags, id: \.name) { tag in
                    SidebarRow(item: .tag(tag.name), count: tag.packageIDs.count, dot: Color(hexString: tag.colorHex) ?? .gray)
                        .contextMenu {
                            Button(String(localized: "Delete Tag"), role: .destructive) { model.userData.deleteTag(tag) }
                        }
                }
                Button { showNewTag = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").frame(width: 18)
                        Text(String(localized: "New Tag…"))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                header(String(localized: "Tools"))
                SidebarRow(item: .history)
                SidebarRow(item: .maintenance)
                SidebarRow(item: .brewfile)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    var count = 0
    var hot = false
    var dot: Color?
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.sidebar == item
        Button { model.sidebar = item } label: {
            HStack(spacing: 10) {
                Group {
                    if let dot {
                        Circle().fill(dot).frame(width: 9, height: 9)
                    } else {
                        Image(systemName: item.symbol).font(.system(size: 13))
                    }
                }
                .frame(width: 18)
                .foregroundStyle(on ? Theme.accentText : Theme.text2)
                Text(item.title)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 { CountBadge(count: count, hot: hot) }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.sidebarSelection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(item.title), \(count)" : item.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "Ready to brew" status card at the bottom of the sidebar.
struct StatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let formulae = model.formulaCount
        let casks = model.caskCount
        let busy = model.operations.running
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(busy != nil ? Theme.accent : (model.catalogError != nil ? Theme.red : Theme.green)).frame(width: 7, height: 7)
                Text(busy?.title ?? (model.isRefreshingCatalog ? String(localized: "Refreshing index…") : String(localized: "Ready to brew")))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            Text(statusLine(formulae: formulae, casks: casks))
                .font(.system(size: 11)).foregroundStyle(Theme.text2).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chip))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    private func statusLine(formulae: Int, casks: Int) -> String {
        if let err = model.catalogError { return err }
        if model.isCatalogLoading { return String(localized: "Loading Homebrew's index…") }
        let when = model.catalogGeneratedAt ?? model.catalogLoadedAt
        let counts = String(localized: "\(formulae.formatted()) formulae, \(casks.formatted()) casks")
        guard let when else { return counts }
        return String(localized: "Index refreshed \(when.relative) · \(counts)")
    }
}

// MARK: Toolbar

struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { BackForwardButtons() }
        ToolbarItem(placement: .principal) { SearchPill() }
        ToolbarItemGroup(placement: .primaryAction) {
            UpdateButton()
            ActivityButton()
            MoreMenuButton()
        }
    }
}

private struct BackForwardButtons: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left").frame(width: 30) }
                .disabled(!model.canGoBack)
                .help(String(localized: "Back"))
            Button { model.goForward() } label: { Image(systemName: "chevron.right").frame(width: 30) }
                .disabled(!model.canGoForward)
                .help(String(localized: "Forward"))
        }
    }
}

private struct UpdateButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.updateHomebrew() } label: { Image(systemName: "arrow.clockwise") }
            .help(String(localized: "Update Homebrew — refresh package metadata (⌘R). Doesn't upgrade anything."))
    }
}

private struct MoreMenuButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        LazyMenuButton {
            [MenuEntry(String(localized: "Upgrade All")) { model.upgradeAll() },
             MenuEntry(String(localized: "Remove Unused Dependencies…")) { model.pendingSheet = .autoremove },
             MenuEntry(String(localized: "Run brew doctor")) { model.showDoctor() },
             MenuEntry(String(localized: "Clean Up Old Versions…")) { model.showCleanup() },
             .separator,
             MenuEntry(String(localized: "Export Brewfile…")) { model.sidebar = .brewfile },
             MenuEntry(String(localized: "Add Tap…")) { model.pendingSheet = .addTap }]
        } label: {
            Image(systemName: "ellipsis")
        }
        .help(String(localized: "More"))
    }
}

/// Toolbar search: filters the current list as you type; ⌘K opens the palette.
struct SearchPill: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var hintIndex = 0
    @State private var showFilters = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Text("❯").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentText)
            TextField(placeholder, text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit {
                    if SmartSearch.looksLikeNaturalLanguage(model.searchText) {
                        let text = model.searchText
                        Task { await model.smartSearch(text) }
                    } else if !model.isListScreen(model.sidebar) {
                        model.sidebar = .allPackages
                    }
                }
                .onKeyPress(.escape) {
                    model.searchText = ""
                    focused = false
                    return .handled
                }
                .onChange(of: model.searchText) { _, new in
                    if !new.isEmpty && !model.isListScreen(model.sidebar) { model.sidebar = .allPackages }
                }
                .accessibilityLabel(String(localized: "Search packages"))
            if model.isSmartSearching {
                ProgressView().controlSize(.small)
            } else if SmartSearch.looksLikeNaturalLanguage(model.searchText) {
                Button {
                    let text = model.searchText
                    Task { await model.smartSearch(text) }
                } label: {
                    Label(String(localized: "Smart search"), systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Turn this into search filters (↵)"))
            }
            Button { showFilters.toggle() } label: {
                Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Search filters"))
            .accessibilityLabel(String(localized: "Search filters"))
            .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                SearchFiltersHelp { token in
                    let current = model.searchText.trimmingCharacters(in: .whitespaces)
                    model.searchText = current.isEmpty ? token : current + " " + token
                    showFilters = false
                    focused = true
                }
            }
            Button { model.showPalette = true } label: { KeyCap(text: "⌘K") }
                .buttonStyle(.plain)
                .help(AppInfo.fullTagline)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minWidth: 320, idealWidth: 520, maxWidth: 560)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in focused = true }
        // Cycle example searches while the field is idle, so the filters are discoverable.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if !focused && model.searchText.isEmpty { hintIndex &+= 1 }
            }
        }
    }

    private var placeholder: String {
        let hints = [
            String(localized: "Search \(model.packages.count.formatted()) formulae and casks"),
            String(localized: "Try “is:outdated” to see what needs upgrading"),
            String(localized: "Try “type:cask browser”"),
            String(localized: "Try “cat:fonts” or “cat:ai”"),
            String(localized: "Try “is:installed tag:work”"),
            String(localized: "Try “tap:hashicorp”"),
            String(localized: "Describe it: “an app to edit videos” ↵"),
            String(localized: "Press ⌘K for actions like “Upgrade all”")
        ]
        return hints[hintIndex % hints.count]
    }
}

/// Every search filter with an example; clicking one adds it to the search.
struct SearchFiltersHelp: View {
    let insert: (String) -> Void

    static let filters: [(token: String, meaning: String)] = [
        ("is:installed", String(localized: "Only installed packages")),
        ("is:outdated", String(localized: "Packages with an update")),
        ("is:pinned", String(localized: "Pinned formulae")),
        ("is:deprecated", String(localized: "Deprecated packages")),
        ("type:formula", String(localized: "Command-line formulae only")),
        ("type:cask", String(localized: "Apps (casks) only")),
        ("cat:", String(localized: "A category, e.g. cat:fonts, cat:browsers, cat:ai")),
        ("tag:", String(localized: "One of your tags, e.g. tag:work")),
        ("tap:", String(localized: "A tap, e.g. tap:hashicorp"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Search filters")).font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Combine filters with words: “type:cask is:outdated”, “cat:ai chat”. Or just describe what you need (“a tool to compress images”) and press Return."))
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.filters, id: \.token) { f in
                    Button { insert(f.token) } label: {
                        HStack(spacing: 12) {
                            Text(f.token).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 110, alignment: .leading)
                            Text(f.meaning).font(.system(size: 12)).foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

struct ActivityButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.showActivity.toggle() } label: {
            ZStack {
                if model.operations.hasActive {
                    if let p = model.operations.overallProgress {
                        Circle().trim(from: 0, to: p).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 16, height: 16)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        }
        .help(String(localized: "Activity (⌘L)"))
        .accessibilityLabel(String(localized: "Activity"))
        .accessibilityValue(model.operations.hasActive ? String(localized: "\(model.operations.active.count) running") : "")
    }
}

// MARK: Toasts & HUD

struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { t in
                HStack(spacing: 8) {
                    Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.isError ? Theme.red : Theme.green)
                    Text(t.text).font(.system(size: 13, weight: .medium))
                    if t.isError {
                        Button(String(localized: "Details")) { model.showActivity = true }.buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.bottom, model.showActivity ? 300 : 24)
        .animation(.spring(duration: 0.25), value: model.toasts)
    }
}

struct PerfHUD: View {
    var body: some View {
        let log = PerfLog.shared
        VStack(alignment: .leading, spacing: 3) {
            Text("Performance").font(.system(size: 11, weight: .bold))
            ForEach(log.order, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer(minLength: 16)
                    Text(String(format: "%.1f ms", log.latest[name] ?? 0)).monospacedDigit()
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .frame(width: 240)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}
