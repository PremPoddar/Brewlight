import Charts
import SwiftUI

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: MaintenanceParsers.Suggestion?
    /// Warnings start expanded so their suggested fixes are visible.
    @State private var collapsed: Set<UUID> = []
    @State private var config = ""
    @State private var dirSizes: [(String, Int64)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: String(localized: "Maintenance"), subtitle: String(localized: "Keep Homebrew healthy and reclaim disk space"))
                diskUsage
                HStack(alignment: .top, spacing: 14) {
                    doctorCard
                    VStack(spacing: 14) {
                        cleanupCard
                        autoremoveCard
                    }
                }
                configCard
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
        .task {
            if model.sizes.isEmpty { await model.computeSizes() }
            await loadDirSizes()
        }
    }

    private func card<C: View>(_ title: String, symbol: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
    }

    // MARK: Disk usage

    private var diskUsage: some View {
        let largest = model.sizes.sorted { $0.value > $1.value }.prefix(12)
        return card(String(localized: "Disk usage"), symbol: "internaldrive") {
            HStack(spacing: 24) {
                ForEach(dirSizes, id: \.0) { name, size in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                        Text(size.byteString).font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                }
            }
            if largest.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Chart(Array(largest), id: \.key) { item in
                    BarMark(x: .value("Size", Double(item.value) / 1_000_000), y: .value("Package", model.package(item.key)?.token ?? item.key))
                        .foregroundStyle(Theme.accent.gradient)
                        .annotation(position: .trailing) {
                            Text(item.value.byteString).font(.system(size: 10)).foregroundStyle(Theme.text2)
                        }
                }
                .chartXAxisLabel("MB")
                .frame(height: CGFloat(largest.count) * 24 + 20)
                .accessibilityLabel(String(localized: "Largest installed packages"))
            }
        }
    }

    private func loadDirSizes() async {
        guard let env = model.env, !AppInfo.isDemo else {
            dirSizes = [(String(localized: "Installed packages"), model.totalInstalledSize)]
            return
        }
        dirSizes = await Task.detached(priority: .utility) {
            [(String(localized: "Cellar"), Paths.diskSize(env.cellar)),
             (String(localized: "Caskroom"), Paths.diskSize(env.caskroom)),
             (String(localized: "Download cache"), Paths.diskSize(env.cache))]
        }.value
    }

    // MARK: Doctor

    private var doctorCard: some View {
        card(String(localized: "brew doctor"), symbol: "stethoscope") {
            if let doctor = model.doctorWarnings {
                if doctor.isEmpty {
                    Label(String(localized: "Your system is ready to brew."), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else {
                    Text(doctor.count == 1 ? String(localized: "1 warning") : String(localized: "\(doctor.count) warnings"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                    ForEach(doctor) { w in
                        let fixes = MaintenanceParsers.suggestions(for: w).count
                        DisclosureGroup(isExpanded: Binding(
                            get: { !collapsed.contains(w.id) },
                            set: { if $0 { collapsed.remove(w.id) } else { collapsed.insert(w.id) } })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(w.body).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                suggestions(for: w)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Label(w.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).font(.system(size: 12, weight: .medium))
                                if fixes > 0 {
                                    Text(fixes == 1 ? String(localized: "1 fix") : String(localized: "\(fixes) fixes"))
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accentText)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Capsule().fill(Theme.accentTint))
                                }
                            }
                        }
                    }
                    Text(String(localized: "Warnings are often harmless. Fix them only if something is actually broken."))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            } else {
                Text(String(localized: "Checks your Homebrew setup for common problems.")).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            HStack {
                Button(model.isRunningDoctor ? String(localized: "Running…") : (model.doctorWarnings == nil ? String(localized: "Run Doctor") : String(localized: "Run Again"))) {
                    Task { await model.runDoctor() }
                }
                .buttonStyle(.glass)
                .disabled(model.isRunningDoctor)
                if model.isRunningDoctor { ProgressView().controlSize(.small) }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { s in
            switch s {
            case .brew(let args):
                Button(String(localized: "Run")) {
                    model.operations.enqueue("brew " + args.joined(separator: " "), args, packages: [])
                    model.showActivity = true
                }
            case .terminal(let command):
                Button(String(localized: "Open in Terminal")) { model.runInTerminal(command) }
            default: EmptyView()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { s in
            switch s {
            case .brew(let args): Text("brew " + args.joined(separator: " "))
            case .terminal(let command):
                Text(String(localized: "Terminal will run:\n\(command)\n\nIt asks for your administrator password there; Brewlight never sees it."))
            default: EmptyView()
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .terminal?: String(localized: "Run this command in Terminal?")
        case .brew?: String(localized: "Run this Homebrew command?")
        default: ""
        }
    }

    /// Buttons for what the warning says you can do.
    @ViewBuilder
    private func suggestions(for w: MaintenanceParsers.DoctorWarning) -> some View {
        let items = MaintenanceParsers.suggestions(for: w)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Suggested")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                FlowLayout(spacing: 6) {
                    ForEach(items) { item in suggestionButton(item) }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func suggestionButton(_ s: MaintenanceParsers.Suggestion) -> some View {
        switch s {
        case .package(let name):
            if let p = model.package(named: name) {
                Button(String(localized: "Show \(name)")) { model.reveal(p.id) }.buttonStyle(.glass)
                if model.isInstalled(p.id) {
                    Button(String(localized: "Uninstall \(name)…")) { model.pendingSheet = .uninstall(p.id) }.buttonStyle(.glass)
                }
                if let r = p.replacement {
                    Button(String(localized: "Replacement: \(r)")) { model.reveal(Package.id(p.kind, r)) }.buttonStyle(.glass)
                }
            }
        case .brew(let args):
            Button(String(localized: "Run “brew \(args.joined(separator: " "))”…")) { confirm = s }.buttonStyle(.glassProminent)
        case .terminal:
            Button(String(localized: "Run in Terminal…")) { confirm = s }.buttonStyle(.glass)
                .help(String(localized: "Needs your administrator password, so it runs in Terminal"))
        case .link(let url):
            Link(String(localized: "Open \(url.host() ?? "link") ↗"), destination: url).font(.system(size: 12))
        }
    }

    // MARK: Cleanup

    private var cleanupCard: some View {
        @Bindable var model = model
        return card(String(localized: "Clean up"), symbol: "trash") {
            Text(String(localized: "Removes old versions and stale downloads.")).font(.system(size: 12)).foregroundStyle(Theme.text2)
            Toggle(String(localized: "Also clear all cached downloads (--prune=all)"), isOn: $model.cleanupPruneAll).toggleStyle(.checkbox).font(.system(size: 12))
            if let cleanup = model.cleanupPreview {
                Text(cleanup.reclaimable.map { String(localized: "\($0) can be freed (\(cleanup.items.count) items)") } ?? String(localized: "Nothing to clean up."))
                    .font(.system(size: 13, weight: .semibold))
                if !cleanup.items.isEmpty {
                    DisclosureGroup(String(localized: "Show items")) {
                        Text(cleanup.items.joined(separator: "\n")).font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .font(.system(size: 12))
                }
            }
            HStack {
                Button(model.isPreviewingCleanup ? String(localized: "Checking…") : String(localized: "Preview")) {
                    Task { await model.previewCleanup() }
                }
                .buttonStyle(.glass)
                .disabled(model.isPreviewingCleanup)
                Button(String(localized: "Clean Up")) { model.runCleanup() }
                    .buttonStyle(.glassProminent)
                    .disabled(model.cleanupPreview == nil || model.cleanupPreview?.items.isEmpty == true)
                    .help(model.cleanupPreview == nil ? String(localized: "Preview first to see what will be removed") : "")
                if model.isPreviewingCleanup { ProgressView().controlSize(.small) }
            }
        }
    }

    private var autoremoveCard: some View {
        card(String(localized: "Unused dependencies"), symbol: "leaf") {
            let orphans = model.graph.orphans(installed: model.installedFormulaNames, requested: model.requestedFormulaNames)
            Text(orphans.isEmpty ? String(localized: "No unused dependencies found.") : String(localized: "About \(orphans.count) dependencies look unused."))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            Button(String(localized: "Review & Remove…")) { model.pendingSheet = .autoremove }.buttonStyle(.glass)
        }
    }

    // MARK: Config

    private var configCard: some View {
        card(String(localized: "brew config"), symbol: "info.circle") {
            if config.isEmpty {
                Button(String(localized: "Show Configuration")) {
                    Task { config = await model.runner?.output(["config"]).stdout ?? "" }
                }
                .buttonStyle(.glass)
            } else {
                Text(config).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Copy")) { model.copy(config) }.buttonStyle(.glass)
            }
        }
    }
}
