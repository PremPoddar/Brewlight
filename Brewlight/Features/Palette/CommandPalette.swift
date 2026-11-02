import SwiftUI

/// ⌘K quick switcher: searches packages and actions as you type.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var cursor = 0
    @State private var results: [Package] = []
    /// When set, the list shows this package's actions (opened with Tab), and Esc goes back.
    @State private var actionsFor: Package?
    @FocusState private var focused: Bool
    @Environment(\.openWindow) private var openWindow

    struct PaletteAction: Identifiable {
        let id: String
        let glyph: String
        let label: String
        var meta = ""
        var key = ""
        var accent = false
        let run: @MainActor () -> Void
    }

    enum Item: Identifiable {
        case package(Package)
        case action(PaletteAction)
        var id: String {
            switch self {
            case .package(let p): p.id
            case .action(let a): "action:" + a.id
            }
        }
    }

    var body: some View {
        let actions = actionsFor.map(packageActions) ?? actionResults(top: results.first)
        let shownResults = actionsFor == nil ? results : []
        let items: [Item] = shownResults.map(Item.package) + actions.map(Item.action)

        ZStack(alignment: .top) {
            Theme.dim.ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                inputRow
                if let p = actionsFor {
                    actionsList(for: p, actions: actions)
                } else if query.isEmpty && results.isEmpty {
                    emptyState(actions: actions)
                } else {
                    resultsList(results: results, actions: actions, items: items)
                }
                footer(count: items.count)
            }
            .frame(width: 720)
            .foregroundStyle(Theme.text)
            // Tinted base keeps results legible over busy content and when glass is reduced.
            .background(Theme.detail.opacity(0.86), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.top, 110)
            .onKeyPress(.downArrow) { cursor = min(cursor + 1, max(items.count - 1, 0)); return .handled }
            .onKeyPress(.upArrow) { cursor = max(cursor - 1, 0); return .handled }
            .onKeyPress(.tab) {
                // On a package: show everything you can do with it. Otherwise jump to the actions.
                if actionsFor == nil, items.indices.contains(cursor), case .package(let p) = items[cursor] {
                    actionsFor = p
                    cursor = 0
                } else if actionsFor == nil {
                    cursor = cursor < shownResults.count ? shownResults.count : 0
                }
                return .handled
            }
            .onKeyPress(.escape) {
                if actionsFor != nil { actionsFor = nil; cursor = 0 }
                else if query.isEmpty { close() } else { query = "" }
                return .handled
            }
            .onKeyPress(keys: [.return]) { press in
                guard items.indices.contains(cursor) else { return .handled }
                activate(items[cursor], install: press.modifiers.contains(.command))
                return .handled
            }
        }
        .onAppear { focused = true; query = model.paletteSeed; model.paletteSeed = "" }
        // Asking for focus in onAppear can happen before the field is in the window; ask again
        // once it is, so ⌘K always lands the cursor in the field.
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
        .onChange(of: query, initial: true) {
            cursor = 0
            actionsFor = nil
            results = packageResults
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Pieces

    private var inputRow: some View {
        HStack(spacing: 14) {
            Text("❯").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accentText)
            TextField(String(localized: "Search everything in brew…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 24))
                .tracking(-0.4)
                .focused($focused)
                .accessibilityLabel(String(localized: "Command palette search"))
            KeyCap(text: "esc")
        }
        .padding(.leading, 26).padding(.trailing, 18)
        .frame(height: 68)
    }

    private func emptyState(actions: [PaletteAction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppInfo.fullTagline).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 14).padding(.top, 10)
            Text(String(localized: "Filters: is:installed · is:outdated · type:cask · cat:fonts · tag:work · tap:hashicorp"))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text3)
                .padding(.horizontal, 14).padding(.bottom, 6)
            groupLabel(String(localized: "Actions"))
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                actionRow(a, selected: cursor == i).onTapGesture { a.run(); close() }
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
        .background(Theme.list.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func resultsList(results: [Package], actions: [PaletteAction], items: [Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let top = results.first {
                        groupLabel(String(localized: "Top Hit"))
                        topHit(top, selected: cursor == 0).id(top.id)
                            .onTapGesture { activate(.package(top), install: false) }
                    }
                    let formulae = results.dropFirst().filter { $0.kind == .formula }
                    let casks = results.dropFirst().filter { $0.kind == .cask }
                    if !formulae.isEmpty {
                        groupLabel(String(localized: "Formulae"))
                        ForEach(formulae) { p in
                            resultRow(p, selected: items.indices.contains(cursor) && items[cursor].id == p.id).id(p.id)
                                .onTapGesture { activate(.package(p), install: false) }
                        }
                    }
                    if !casks.isEmpty {
                        groupLabel(String(localized: "Casks"))
                        ForEach(casks) { p in
                            resultRow(p, selected: items.indices.contains(cursor) && items[cursor].id == p.id).id(p.id)
                                .onTapGesture { activate(.package(p), install: false) }
                        }
                    }
                    if !actions.isEmpty {
                        groupLabel(String(localized: "Actions"))
                        ForEach(actions) { a in
                            actionRow(a, selected: items.indices.contains(cursor) && items[cursor].id == "action:" + a.id).id("action:" + a.id)
                                .onTapGesture { a.run(); close() }
                        }
                    }
                    if results.isEmpty && actions.isEmpty {
                        Text(String(localized: "No matches. Try a different name, or filters like is:installed or type:cask."))
                            .font(.system(size: 13)).foregroundStyle(Theme.text2).padding(20)
                    }
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
            }
            .frame(maxHeight: 470)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: cursor) { _, c in
                if items.indices.contains(c) { proxy.scrollTo(items[c].id) }
            }
        }
        .background(Theme.list.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 18) {
            if actionsFor != nil {
                hint("↑↓", String(localized: "Navigate"))
                hint("↵", String(localized: "Run"))
                hint("esc", String(localized: "Back"))
            } else {
                hint("↑↓", String(localized: "Navigate"))
                hint("↵", String(localized: "Open"))
                hint("⌘↵", String(localized: "Install"))
                hint("tab", String(localized: "Actions for selection"))
            }
            Spacer()
            Text(actionsFor == nil ? String(localized: "\(count) results") : String(localized: "\(count) actions"))
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 24)
        .frame(height: 42)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    /// Everything you can do with one package (the same items as its ⋯ menu).
    private func packageActions(_ p: Package) -> [PaletteAction] {
        func flatten(_ entries: [MenuEntry]) -> [MenuEntry] {
            entries.flatMap { e in e.children.map(flatten) ?? [e] }
        }
        return flatten(model.menuEntries(for: p) { openWindow(id: "package", value: $0) })
            .filter { !$0.isSeparator && $0.action != nil && $0.isEnabled }
            .enumerated()
            .map { i, e in
                let action = e.action!
                return PaletteAction(id: "\(i):" + e.title, glyph: e.isOn == true ? "✓" : "›",
                                     label: e.title, accent: i == 0) { action() }
            }
    }

    private func actionsList(for p: Package, actions: [PaletteAction]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PackageIcon(package: p, size: 28, appPath: model.installed[p.id]?.appPaths.first)
                    Text(String(localized: "Actions for \(p.token)")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(String(localized: "Back")) { actionsFor = nil; cursor = 0 }.buttonStyle(.link).font(.system(size: 12))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                    actionRow(a, selected: cursor == i).onTapGesture { a.run(); close() }
                }
            }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
        }
        .frame(maxHeight: 470)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.list.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) { Text(key).fontWeight(.bold); Text(label) }
    }

    private func groupLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
    }

    private func highlighted(_ name: String) -> Text {
        let q = SearchQuery(query).text.lowercased()
        guard !q.isEmpty, let r = name.lowercased().range(of: q) else { return Text(name) }
        let lower = name.lowercased()
        let start = lower.distance(from: lower.startIndex, to: r.lowerBound)
        let len = q.count
        let a = String(name.prefix(start))
        let b = String(name.dropFirst(start).prefix(len))
        let c = String(name.dropFirst(start + len))
        var out = AttributedString(a)
        var mid = AttributedString(b)
        mid.foregroundColor = Theme.accentText
        mid.font = .system(size: 15, weight: .heavy)
        out += mid
        out += AttributedString(c)
        return Text(out)
    }

    private func topHit(_ p: Package, selected: Bool) -> some View {
        let inst = model.installed[p.id]
        return HStack(spacing: 14) {
            PackageIcon(package: p, size: 42, appPath: inst?.appPaths.first)
            VStack(alignment: .leading, spacing: 1) {
                highlighted(p.token).font(.system(size: 15, weight: .semibold))
                Text("\(p.desc) · \(p.kind.badge)").font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            if let inst {
                Text(String(localized: "✓ Installed \(inst.currentVersion)"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chip))
            }
            HStack(spacing: 6) {
                Text(String(localized: "Open")).font(.system(size: 12, weight: .semibold))
                KeyCap(text: "↵")
            }
            moreButton(p)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Theme.accentTint : .clear))
        .contentShape(Rectangle())
    }

    private func resultRow(_ p: Package, selected: Bool) -> some View {
        let inst = model.installed[p.id]
        return HStack(spacing: 14) {
            PackageIcon(package: p, size: 32, appPath: inst?.appPaths.first)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                highlighted(p.token).font(.system(size: 14, weight: .semibold)).lineLimit(1).layoutPriority(1)
                Text(p.desc).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(inst?.currentVersion ?? p.version).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text3).lineLimit(1)
            if inst == nil {
                RowActionButton(title: String(localized: "Install")) { model.pendingSheet = .install([p.id]); close() }
            } else {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text3).frame(width: 60)
            }
            moreButton(p)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Theme.accentTint : .clear))
        .contentShape(Rectangle())
    }

    /// Mouse equivalent of Tab: all actions for this package.
    private func moreButton(_ p: Package) -> some View {
        Button { actionsFor = p; cursor = 0 } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text2)
                .frame(width: 26, height: 26).background(Circle().fill(Theme.chip)).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "More actions (tab)"))
        .accessibilityLabel(String(localized: "More actions for \(p.token)"))
    }

    private func actionRow(_ a: PaletteAction, selected: Bool) -> some View {
        HStack(spacing: 14) {
            Text(a.glyph).font(.system(size: 14, weight: .bold)).foregroundStyle(a.accent ? Theme.accentText : Theme.text2)
                .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(Theme.chip))
            Text(a.label).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(a.meta).font(.system(size: 12)).foregroundStyle(Theme.text2)
            if !a.key.isEmpty { KeyCap(text: a.key) }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Theme.accentTint : .clear))
        .contentShape(Rectangle())
    }

    // MARK: Data

    private var packageResults: [Package] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(model.list(query: query, filter: .init(), sort: .name).prefix(12))
    }

    private func actionResults(top: Package?) -> [PaletteAction] {
        let n = model.upgradableCount
        var all: [PaletteAction] = [
            PaletteAction(id: "upgradeAll", glyph: "↑", label: String(localized: "Upgrade all"), meta: n == 1 ? String(localized: "1 package") : String(localized: "\(n) packages"), key: "⇧⌘U", accent: true) { model.upgradeAll() },
            PaletteAction(id: "update", glyph: "↻", label: String(localized: "Update Homebrew"), meta: String(localized: "refresh metadata"), key: "⌘R") { model.updateHomebrew() },
            PaletteAction(id: "doctor", glyph: "✚", label: String(localized: "Run doctor"), meta: String(localized: "check for problems")) { model.showDoctor() },
            PaletteAction(id: "cleanup", glyph: "⌫", label: String(localized: "Clean up old versions"), meta: String(localized: "preview first")) { model.showCleanup() },
            PaletteAction(id: "autoremove", glyph: "⌧", label: String(localized: "Remove unused dependencies")) { model.pendingSheet = .autoremove },
            PaletteAction(id: "brewfile", glyph: "⎘", label: String(localized: "Export Brewfile")) { model.sidebar = .brewfile },
            PaletteAction(id: "tap", glyph: "⑂", label: String(localized: "Add tap")) { model.pendingSheet = .addTap },
            PaletteAction(id: "activity", glyph: "≡", label: String(localized: "Show activity"), key: "⌘L") { model.showActivity = true },
            PaletteAction(id: "settings", glyph: "⚙", label: String(localized: "Open settings"), key: "⌘,") { openSettings() }
        ]
        if let p = top {
            if model.isInstalled(p.id) {
                all.insert(PaletteAction(id: "reinstall", glyph: "↻", label: String(localized: "Reinstall \(p.token)")) { model.reinstall(p.id) }, at: 1)
                all.insert(PaletteAction(id: "uninstall", glyph: "−", label: String(localized: "Uninstall \(p.token)")) { model.pendingSheet = .uninstall(p.id) }, at: 2)
            } else {
                all.insert(PaletteAction(id: "install", glyph: "+", label: String(localized: "Install \(p.token)"), key: "⌘↵", accent: true) { model.pendingSheet = .install([p.id]) }, at: 0)
            }
            all.insert(PaletteAction(id: "copy", glyph: "❯", label: String(localized: "Copy “\(p.installCommand)”")) { model.copy(p.installCommand) }, at: 2)
        }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return Array(all.prefix(6)) }
        if SmartSearch.looksLikeNaturalLanguage(query) {
            let request = query
            let smart = PaletteAction(id: "smart", glyph: "✦", label: String(localized: "Smart search: “\(request)”"),
                                      meta: SmartSearch.isModelAvailable ? String(localized: "on-device") : "", accent: true) {
                Task { await model.smartSearch(request) }
            }
            return [smart] + Array(all.prefix(3))
        }
        // With a package top hit, show its contextual actions; otherwise match action names.
        let matched = all.filter { $0.label.lowercased().contains(q) }
        return top != nil ? Array((matched + all.prefix(3)).uniqued().prefix(4)) : matched
    }

    private func activate(_ item: Item, install: Bool) {
        switch item {
        case .package(let p):
            if install && !model.isInstalled(p.id) { model.pendingSheet = .install([p.id]) } else { model.reveal(p.id) }
        case .action(let a):
            a.run()
        }
        close()
    }

    private func close() { model.showPalette = false }
}

extension Array where Element == CommandPalette.PaletteAction {
    func uniqued() -> [Element] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
