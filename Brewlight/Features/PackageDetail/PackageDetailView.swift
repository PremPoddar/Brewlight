import SwiftUI

struct PackageDetailWindow: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    var body: some View {
        PackageDetailView(packageID: packageID)
            .background(Theme.detail)
            .navigationTitle(model.package(packageID)?.token ?? packageID)
            .sheet(item: Binding(get: { model.pendingSheet }, set: { model.pendingSheet = $0 })) { SheetRouter(request: $0) }
    }
}

struct PackageDetailView: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showAllDeps = false
    @State private var includeBuildDeps = false
    @State private var note = ""
    @State private var noteLoaded = false
    @State private var editingNote = false
    @State private var showTree = false

    var body: some View {
        if let p = model.package(packageID) ?? model.installed[packageID].map(model.packageOrStub) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header(p)
                    warnings(p)
                    description(p)
                    stats(p)
                    dependencies(p)
                    if let caveats = p.caveats { caveatBox(caveats) }
                    CommandLineBox(command: primaryCommand(p))
                    if p.kind == .cask { caskDetails(p) }
                    if let inst = model.installed[p.id], p.kind == .formula { formulaDetails(p, inst) }
                    VersionsSection(package: p)
                    CacheRow(package: p)
                    dependencyTree(p)
                    userSection(p)
                    links(p)
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            // Same view across selections (cheaper than rebuilding); reset per-package state.
            .onChange(of: packageID) {
                note = model.userData.notes[packageID] ?? ""
                editingNote = false
                showTree = false
                showAllDeps = false
            }
        } else {
            EmptyStateView(symbol: "questionmark.square.dashed", title: String(localized: "Package not found"),
                           message: String(localized: "It may have been removed from Homebrew."))
        }
    }

    // MARK: Header

    private func header(_ p: Package) -> some View {
        let inst = model.installed[p.id]
        let out = model.visibleOutdated[p.id]
        return HStack(alignment: .center, spacing: 18) {
            PackageIcon(package: p, size: 76, appPath: inst?.appPaths.first)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(p.kind == .cask && p.displayName != p.token ? p.displayName : p.token)
                        .font(.system(size: 30, weight: .bold)).tracking(-0.9)
                        .textSelection(.enabled)
                    Button { model.userData.toggleFavourite(p.id) } label: {
                        Image(systemName: model.userData.favourites.contains(p.id) ? "star.fill" : "star")
                            .foregroundStyle(model.userData.favourites.contains(p.id) ? Theme.accent : Theme.text3)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Favourite"))
                    .accessibilityLabel(String(localized: "Favourite"))
                }
                Text(subtitle(p)).font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                primaryButton(p, inst: inst, out: out)
                LazyMenuButton {
                    model.menuEntries(for: p) { openWindow(id: "package", value: $0) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.chip))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "More actions"))
            }
        }
    }

    @ViewBuilder
    private func primaryButton(_ p: Package, inst: InstalledPackage?, out: OutdatedInfo?) -> some View {
        if inst == nil {
            Button(String(localized: "Install")) { model.pendingSheet = .install([p.id]) }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(p.isDisabled)
                .help(p.isDisabled ? String(localized: "This package is disabled in Homebrew") : p.installCommand)
        } else if let out {
            Button(String(localized: "Upgrade to \(out.available)")) { model.upgrade([p.id]) }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(out.pinned)
                .help(out.pinned ? String(localized: "Pinned — unpin to upgrade") : "brew upgrade \(p.token)")
        } else if p.kind == .cask, inst?.appPaths.isEmpty == false {
            Button(String(localized: "Open")) { model.open(p.id) }
                .buttonStyle(PrimaryPillButtonStyle())
        } else {
            Button(String(localized: "Uninstall…")) { model.pendingSheet = .uninstall(p.id) }
                .buttonStyle(ChipButtonStyle())
        }
    }

    private func subtitle(_ p: Package) -> String {
        [p.kind.label, p.tap, p.license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func primaryCommand(_ p: Package) -> String {
        if model.visibleOutdated[p.id] != nil { return p.kind == .cask ? "brew upgrade --cask \(p.token)" : "brew upgrade \(p.token)" }
        if model.isInstalled(p.id) { return p.kind == .cask ? "brew uninstall --cask \(p.token)" : "brew uninstall \(p.token)" }
        return p.installCommand
    }

    // MARK: Body sections

    @ViewBuilder
    private func warnings(_ p: Package) -> some View {
        if let reason = p.disableReason ?? p.deprecationReason {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.isDisabled ? String(localized: "Disabled: \(reason)") : String(localized: "Deprecated: \(reason)"))
                        .font(.system(size: 13, weight: .semibold))
                    if let r = p.replacement {
                        Button(String(localized: "Use \(r) instead")) { model.reveal(Package.id(p.kind, r)) }.buttonStyle(.link)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
        }
    }

    private func description(_ p: Package) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.desc.isEmpty ? String(localized: "No description.") : p.desc)
                .font(.system(size: 15)).lineSpacing(3).textSelection(.enabled)
            if let url = p.homepageURL {
                Link("\(p.homepageHost) ↗", destination: url)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func stats(_ p: Package) -> some View {
        let inst = model.installed[p.id]
        let out = model.visibleOutdated[p.id]
        let transitive = p.kind == .formula ? model.graph.transitiveDependencies(of: p.token) : p.caskFormulaDependencies
        let direct = p.kind == .formula ? p.dependencies.count : p.caskFormulaDependencies.count
        return HStack(alignment: .top, spacing: 10) {
            StatCard(label: String(localized: "Version"), value: inst?.currentVersion ?? p.fullVersion,
                     sub: out.map { String(localized: "\($0.available) available") } ?? (inst == nil ? String(localized: "latest") : String(localized: "up to date")))
            if inst != nil {
                StatCard(label: String(localized: "Size on disk"), value: model.sizes[p.id].map(\.byteString) ?? "—",
                         sub: p.kind == .formula ? (inst!.pouredFromBottle ? String(localized: "bottle") : String(localized: "built from source")) : "")
            } else {
                StatCard(label: String(localized: "Installs · 30 days"), value: model.installs30(p.id) > 0 ? model.installs30(p.id).compact : "—",
                         sub: installsSub(p))
            }
            StatCard(label: String(localized: "Dependencies"), value: "\(transitive.count)", sub: String(localized: "\(direct) direct"))
            if let inst {
                StatCard(label: String(localized: "Installed"), value: inst.installedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "—",
                         sub: installedReason(p, inst))
            } else {
                StatCard(label: String(localized: "Bottle"), value: p.kind == .cask ? "—" : (p.hasBottle ? String(localized: "Yes") : String(localized: "Source")),
                         sub: p.kind == .formula ? String(localized: "for this Mac") : "")
            }
        }
        .task(id: p.id) {
            if inst != nil && model.sizes[p.id] == nil { await model.computeSizes(only: [p.id]) }
        }
    }

    /// "123K · 90d · 1.4M · 1y" from Homebrew's public analytics.
    private func installsSub(_ p: Package) -> String {
        let pop = model.popularity
        let parts = [pop.installs90[p.id].map { "\($0.compact) · 90d" }, pop.installs365[p.id].map { "\($0.compact) · 1y" }].compactMap { $0 }
        return parts.isEmpty ? "" : parts.joined(separator: "  ")
    }

    private func installedReason(_ p: Package, _ inst: InstalledPackage) -> String {
        if inst.installedOnRequest { return String(localized: "on request") }
        let parents = model.dependents(of: p.id)
        if let first = parents.first { return String(localized: "as dependency of \(first)") }
        return String(localized: "as dependency")
    }

    @ViewBuilder
    private func dependencies(_ p: Package) -> some View {
        let direct = p.kind == .formula ? p.dependencies + p.recommendedDependencies : p.caskFormulaDependencies
        let transitive = p.kind == .formula ? model.graph.transitiveDependencies(of: p.token) : []
        let requiredBy = model.dependents(of: p.id)
        if !direct.isEmpty || !requiredBy.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Dependencies")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(String(localized: "\(direct.count) direct · \(max(transitive.count - direct.count, 0)) transitive"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                let shown = showAllDeps ? transitive.isEmpty ? direct : transitive : Array(direct.prefix(12))
                FlowLayout(spacing: 6) {
                    ForEach(shown, id: \.self) { d in
                        Button { model.reveal(Package.id(.formula, d)) } label: {
                            HStack(spacing: 4) {
                                if model.isInstalled(Package.id(.formula, d)) == false {
                                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                        .accessibilityLabel(String(localized: "not installed"))
                                }
                                Text(d)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chip))
                        }
                        .buttonStyle(.plain)
                    }
                    let more = transitive.count - shown.count
                    if more > 0 || showAllDeps {
                        Button(showAllDeps ? String(localized: "Show less") : String(localized: "+\(max(more, 0)) more")) { showAllDeps.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                }
                if !requiredBy.isEmpty {
                    HStack(spacing: 0) {
                        Text(String(localized: "Required by ")).foregroundStyle(Theme.text2)
                        ForEach(Array(requiredBy.prefix(6).enumerated()), id: \.offset) { i, name in
                            Button(name) { model.reveal(model.package(named: name)?.id ?? Package.id(.formula, name)) }
                                .buttonStyle(.plain).fontWeight(.medium)
                            if i < min(requiredBy.count, 6) - 1 { Text(", ").foregroundStyle(Theme.text2) }
                        }
                        if requiredBy.count > 6 { Text(String(localized: " and \(requiredBy.count - 6) more")).foregroundStyle(Theme.text2) }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func caveatBox(_ caveats: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.accentInk)
                    .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                Text(String(localized: "Caveats")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(String(localized: "Copy")) { model.copy(caveats) }.buttonStyle(.link).font(.system(size: 12))
            }
            Text(caveats.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.caveat))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.caveatBorder))
    }

    // MARK: Kind-specific

    private func caskDetails(_ p: Package) -> some View {
        DetailSection(title: String(localized: "Cask")) {
            InfoRow(String(localized: "Apps"), p.appNames.isEmpty ? "—" : p.appNames.joined(separator: ", "))
            if !p.binaries.isEmpty { InfoRow(String(localized: "Binaries"), p.binaries.joined(separator: ", ")) }
            if !p.pkgs.isEmpty { InfoRow(String(localized: "Installer packages"), p.pkgs.joined(separator: ", ")) }
            InfoRow(String(localized: "Updates itself"), p.autoUpdates ? String(localized: "Yes") : String(localized: "No"))
            if let mac = p.macOSRequirement { InfoRow(String(localized: "Requires macOS"), mac) }
            if !p.conflicts.isEmpty { InfoRow(String(localized: "Conflicts with"), p.conflicts.joined(separator: ", ")) }
            if !p.zapPaths.isEmpty {
                DisclosureGroup(String(localized: "Leftover files “Remove completely” deletes (\(p.zapPaths.count))")) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(p.zapPaths, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.system(size: 12))
            }
        }
    }

    private func formulaDetails(_ p: Package, _ inst: InstalledPackage) -> some View {
        DetailSection(title: String(localized: "Installation")) {
            InfoRow(String(localized: "Installed versions"), inst.versions.joined(separator: ", "))
            InfoRow(String(localized: "Linked"), inst.linkedVersion ?? String(localized: "Not linked"))
            InfoRow(String(localized: "Installed"), inst.installedOnRequest ? String(localized: "On request") : String(localized: "As a dependency"))
            InfoRow(String(localized: "Source"), inst.pouredFromBottle ? String(localized: "Poured from bottle") : String(localized: "Built from source"))
            if p.kegOnly { InfoRow(String(localized: "Keg-only"), String(localized: "Not symlinked into \(model.env?.prefix.path ?? "the prefix")")) }
            if p.hasService { InfoRow(String(localized: "Service"), String(localized: "Available — see Services")) }
            if let d = inst.installedAt { InfoRow(String(localized: "Install date"), d.formatted(date: .abbreviated, time: .shortened)) }
            HStack {
                Button(String(localized: "Show Files in Finder")) { model.showInFinder(p.id) }
                if !inst.installedOnRequest {
                    Button(String(localized: "Why Is This Installed?")) { model.pendingSheet = .whyInstalled(p.id) }
                }
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func dependencyTree(_ p: Package) -> some View {
        if p.kind == .formula && !(p.dependencies.isEmpty && p.buildDependencies.isEmpty) {
            DetailSection(title: String(localized: "Dependency Tree")) {
                HStack {
                    Button {
                        showTree.toggle()
                    } label: {
                        Label(showTree ? String(localized: "Hide tree") : String(localized: "Show tree"),
                              systemImage: showTree ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                    if showTree {
                        Toggle(String(localized: "Include build dependencies"), isOn: $includeBuildDeps).toggleStyle(.checkbox)
                    }
                    Spacer()
                    Button(String(localized: "Open Graph")) { model.pendingSheet = .graph(p.id) }.buttonStyle(.glass)
                }
                .font(.system(size: 12))
                // Built only on demand: a 50-node tree is cheap, but not free on every click.
                let tree = showTree ? model.graph.tree(of: p.token, includeBuild: includeBuildDeps) : []
                OutlineGroup(tree, children: \.children) { node in
                    HStack(spacing: 6) {
                        Image(systemName: model.isInstalled(Package.id(.formula, node.name)) ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(model.isInstalled(Package.id(.formula, node.name)) ? Theme.green : Theme.text3)
                            .font(.system(size: 11))
                        Button(node.name) { model.reveal(Package.id(.formula, node.name)) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                        if node.isRepeat { Text(String(localized: "(see above)")).font(.system(size: 11)).foregroundStyle(Theme.text3) }
                    }
                }
            }
        }
    }

    private func userSection(_ p: Package) -> some View {
        DetailSection(title: String(localized: "Your Notes & Tags")) {
            FlowLayout(spacing: 6) {
                ForEach(model.userData.tags, id: \.name) { tag in
                    let on = tag.packageIDs.contains(p.id)
                    Button { model.userData.toggle(tag: tag, on: p.id) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hexString: tag.colorHex) ?? .gray).frame(width: 7, height: 7)
                            Text(tag.name)
                        }
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Theme.accentTint : Theme.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if model.userData.tags.isEmpty {
                    Text(String(localized: "Create tags from the sidebar to organise packages.")).font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
            }
            // A Menu (built when opened) instead of a Picker: no 19 menu items created per click.
            LazyMenuButton {
                let current = model.category(of: p)
                return PackageCategory.allCases.map { cat in
                    MenuEntry(cat.localizedName, isOn: cat == current) {
                        model.userData.setCategory(cat, for: p.id)
                        model.reassignCategories()
                    }
                }
            } label: {
                Text(String(localized: "Category: \(model.category(of: p).localizedName) ▾"))
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            if !editingNote && note.isEmpty && (model.userData.notes[p.id] ?? "").isEmpty {
                Button(String(localized: "Add a private note…")) { editingNote = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            } else {
            TextEditor(text: $note)
                .font(.system(size: 13))
                .frame(minHeight: 70)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator))
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text(String(localized: "Private note (Markdown)…")).font(.system(size: 13)).foregroundStyle(Theme.text3)
                            .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                    }
                }
                .onAppear { if !noteLoaded { note = model.userData.notes[p.id] ?? ""; noteLoaded = true } }
                .onChange(of: note) { _, new in
                    if new != (model.userData.notes[p.id] ?? "") { model.userData.setNote(new, for: p.id) }
                }
                .accessibilityLabel(String(localized: "Private note"))
            }
        }
    }

    private func links(_ p: Package) -> some View {
        HStack(spacing: 16) {
            if let url = p.homepageURL { Link(String(localized: "Homepage"), destination: url) }
            if let url = p.sourceURL { Link(String(localized: "Source"), destination: url) }
            if let url = p.releasesURL { Link(String(localized: "Releases"), destination: url) }
            if let url = p.issuesURL { Link(String(localized: "Issues"), destination: url) }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.accentText)
    }
}

// MARK: Helpers

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.text2).frame(width: 150, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
