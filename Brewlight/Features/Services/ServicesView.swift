import SwiftUI

struct ServicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Services"),
                             subtitle: String(localized: "Background services managed by brew services")) {
                    Button(String(localized: "Refresh")) { Task { await model.refreshServices() } }.buttonStyle(ChipButtonStyle())
                }
                if model.services.isEmpty {
                    EmptyStateView(symbol: "dot.radiowaves.left.and.right", title: String(localized: "No services"),
                                   message: String(localized: "Formulae like postgresql or redis provide services you can start here."))
                        .frame(minHeight: 300)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.services) { s in ServiceRow(service: s) }
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
                }
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
        // Short poll while visible.
        .task {
            while !Task.isCancelled {
                await model.refreshServices()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

struct ServiceRow: View {
    let service: BrewService
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.name).font(.system(size: 13, weight: .semibold))
                    if service.user == "root" { KindBadgeText(text: "root") }
                }
                Text(details).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            Text(service.status.capitalized).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Menu {
                Button(String(localized: "Run Once")) { model.service("run", service.name) }
                Button(String(localized: "Restart")) { model.service("restart", service.name) }
                Divider()
                if let prefix = model.env?.prefix {
                    ForEach(service.logFiles(prefix: prefix), id: \.self) { url in
                        Button(String(localized: "Open \(url.lastPathComponent) in Console")) {
                            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"), configuration: .init())
                        }
                    }
                }
                if let file = service.file {
                    Button(String(localized: "Reveal plist")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (file as NSString).expandingTildeInPath)]) }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            if service.isRunning {
                Button(String(localized: "Stop")) { model.service("stop", service.name) }.buttonStyle(ChipButtonStyle(height: 28))
            } else {
                Button(String(localized: "Start")) { model.service("start", service.name) }
                    .buttonStyle(PrimaryPillButtonStyle(height: 28))
                    .help(String(localized: "Start now and at login"))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private var color: Color {
        if service.isRunning { return Theme.green }
        if service.isError { return Theme.red }
        return Theme.text3
    }

    private var details: String {
        var parts: [String] = []
        if let pid = service.pid { parts.append("PID \(pid)") }
        if let code = service.exitCode, code != 0 { parts.append(String(localized: "exit \(code)")) }
        if let file = service.file { parts.append((file as NSString).lastPathComponent) }
        return parts.isEmpty ? String(localized: "Not loaded") : parts.joined(separator: " · ")
    }
}

struct KindBadgeText: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
            .padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.separator))
    }
}

// MARK: Taps

struct TapsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemove: BrewTap?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Taps"), subtitle: String(localized: "Package repositories Homebrew reads from")) {
                    Button(String(localized: "Add Tap…")) { model.pendingSheet = .addTap }.buttonStyle(PrimaryPillButtonStyle())
                }
                VStack(spacing: 0) {
                    ForEach(model.taps) { tap in
                        HStack(spacing: 14) {
                            Image(systemName: tap.isOfficial ? "checkmark.seal.fill" : "exclamationmark.shield")
                                .foregroundStyle(tap.isOfficial ? Theme.accentText : .orange)
                                .accessibilityLabel(tap.isOfficial ? String(localized: "Official") : String(localized: "Third-party"))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(tap.name).font(.system(size: 13, weight: .semibold))
                                    KindBadgeText(text: tap.isOfficial ? String(localized: "official") : String(localized: "third-party"))
                                    if tap.trusted == false {
                                        Text(String(localized: "not trusted — packages ignored"))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.warning)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.warning.opacity(0.14)))
                                    }
                                }
                                Text(tap.remote ?? "").font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
                            }
                            Spacer()
                            Text(String(localized: "\(tap.formulaCount) formulae · \(tap.caskCount) casks")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                            if tap.trusted == false {
                                Button(String(localized: "Trust…")) { model.pendingNotice = .untrustedTaps([tap.name]) }
                                    .buttonStyle(.link).font(.system(size: 12))
                                    .help(String(localized: "Let Homebrew load this tap's formulae, casks and commands"))
                            }
                            Button(String(localized: "Browse")) {
                                model.searchText = "tap:\(tap.name) "
                                model.sidebar = .allPackages
                            }
                            .buttonStyle(.link).font(.system(size: 12))
                            if !tap.isOfficial || !["homebrew/core", "homebrew/cask"].contains(tap.name) {
                                Button(String(localized: "Remove")) { confirmRemove = tap }.buttonStyle(.link).font(.system(size: 12))
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 58)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
        .task { await model.refreshTaps() }
        .alert(String(localized: "Remove tap \(confirmRemove?.name ?? "")?"), isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button(String(localized: "Remove"), role: .destructive) { if let t = confirmRemove { model.removeTap(t.name) } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            let n = model.installed.values.filter { $0.tap == confirmRemove?.name }.count
            Text(n > 0 ? String(localized: "\(n) installed packages come from this tap. Homebrew will refuse until they are uninstalled.") : String(localized: "You can add it again later."))
        }
    }
}

// MARK: Categories

struct CategoriesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Categories"),
                             subtitle: String(localized: "Curated where known, guessed from descriptions otherwise"))
                Columns(items: PackageCategory.allCases, count: 4, spacing: 14) { cat in
                        Button { model.sidebar = .category(cat.rawValue) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: cat.symbol).font(.system(size: 18)).foregroundStyle(Theme.accentText)
                                    .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 11).fill(Theme.accentTint))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.localizedName).font(.system(size: 13, weight: .semibold))
                                    Text(String(localized: "\(model.categoryCounts[cat] ?? 0) packages")).font(.system(size: 11)).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
    }
}

// MARK: History

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var failuresOnly = false
    @State private var entries: [HistoryEntry] = []
    @State private var expanded: Set<PersistentIdentifierBox> = []

    struct PersistentIdentifierBox: Hashable { let date: Date; let command: String }

    var body: some View {
        let filtered = entries.filter { e in
            (!failuresOnly || !e.succeeded) &&
            (query.isEmpty || e.command.localizedCaseInsensitiveContains(query) || e.title.localizedCaseInsensitiveContains(query))
        }
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: String(localized: "History"), subtitle: String(localized: "Everything Brewlight has run, plus install dates from Homebrew's receipts")) {
                HStack {
                    TextField(String(localized: "Filter"), text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
                    Toggle(String(localized: "Failures only"), isOn: $failuresOnly).toggleStyle(.checkbox)
                    Button(String(localized: "Export…")) { export() }.buttonStyle(ChipButtonStyle())
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 36).padding(.top, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if filtered.isEmpty {
                            Text(String(localized: "No operations yet.")).foregroundStyle(Theme.text2).font(.system(size: 12))
                        }
                        ForEach(filtered, id: \.persistentModelID) { e in
                            DisclosureGroup {
                                Text(e.logExcerpt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                HStack {
                                    Image(systemName: e.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                        .foregroundStyle(e.succeeded ? Theme.green : Theme.red)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.title).font(.system(size: 13, weight: .medium))
                                        Text(e.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2)
                                    }
                                    Spacer()
                                    Text("\(Int(e.duration))s").font(.system(size: 11)).foregroundStyle(Theme.text3)
                                    Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                                }
                            }
                        }
                    } header: {
                        sectionHeader(String(localized: "Brewlight operations"))
                    }
                    Section {
                        ForEach(outsideInstalls) { i in
                            HStack {
                                Text(i.token).font(.system(size: 12, weight: .medium))
                                KindBadge(kind: i.kind)
                                Spacer()
                                Text(i.installedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—").font(.system(size: 12)).foregroundStyle(Theme.text2)
                            }
                            .frame(height: 24)
                        }
                    } header: {
                        sectionHeader(String(localized: "Install dates from Homebrew"))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 30)
            }
        }
        .background(Theme.list)
        .onAppear { entries = model.userData.history() }
        .onChange(of: model.operations.operations.filter(\.state.isFinished).count) { entries = model.userData.history() }
    }

    private var outsideInstalls: [InstalledPackage] {
        model.installed.values.filter(\.installedOnRequest)
            .sorted { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(Theme.list)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "brewlight-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows = entries.map { ["date": $0.date.ISO8601Format(), "title": $0.title, "command": $0.command, "succeeded": $0.succeeded ? "true" : "false", "duration": String($0.duration)] }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) { try? data.write(to: url) }
    }
}
