import SwiftUI

struct SheetRouter: View {
    let request: SheetRequest
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch request {
            case .install(let ids): InstallSheet(ids: ids)
            case .uninstall(let id): UninstallSheet(packageID: id)
            case .removeCompletely(let id): RemoveCompletelySheet(packageID: id)
            case .autoremove: AutoremoveSheet()
            case .addTap: AddTapSheet()
            case .graph(let id): DependencyGraphSheet(packageID: id)
            case .switchVersion(let id): SwitchVersionSheet(packageID: id)
            case .removeOldVersions(let id): RemoveOldVersionsSheet(packageID: id)
            case .clearCache(let id): ClearCacheSheet(packageID: id)
            case .whyInstalled(let id): WhyInstalledSheet(packageID: id)
            case .brewfileImport(let url): BrewfileImportSheet(url: url)
            }
        }
        .environment(model)
    }
}

private struct SheetChrome<Content: View, Buttons: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.4)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
            }
            content
            HStack { Spacer(); buttons }
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: Install

struct InstallSheet: View {
    let ids: [String]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var options = InstallOptions()
    @State private var showOptions = false
    @State private var chosenVersion: String?

    var body: some View {
        let pkgs = ids.compactMap(model.package)
        let alreadyInstalled = pkgs.filter { model.isInstalled($0.id) }
        let deps = model.newDependencies(for: ids)
        let single = pkgs.count == 1 ? pkgs.first : nil
        SheetChrome(title: pkgs.count == 1 ? String(localized: "Install \(pkgs[0].token)?") : String(localized: "Install \(pkgs.count) packages?"),
                    subtitle: single?.desc ?? "") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pkgs.prefix(6)) { p in
                    HStack(spacing: 10) {
                        PackageIcon(package: p, size: 28)
                        Text(p.token).fontWeight(.semibold)
                        KindBadge(kind: p.kind)
                        Spacer()
                        Text(p.version).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text2)
                    }
                }
                if pkgs.count > 6 { Text(String(localized: "and \(pkgs.count - 6) more")).foregroundStyle(Theme.text2) }

                if !deps.isEmpty {
                    DisclosureGroup(String(localized: "Also installs \(deps.count) dependencies")) {
                        Text(deps.joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    .font(.system(size: 12))
                }
                if !alreadyInstalled.isEmpty {
                    Label(String(localized: "\(alreadyInstalled.map(\.token).joined(separator: ", ")) is already installed — it will be reinstalled."),
                          systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                if let p = single, !p.versionedFormulae.isEmpty {
                    Picker(String(localized: "Version"), selection: Binding(get: { chosenVersion ?? p.token }, set: { chosenVersion = $0 })) {
                        Text("\(p.token) (\(p.version))").tag(p.token)
                        ForEach(p.versionedFormulae, id: \.self) { Text($0).tag($0) }
                    }
                    .font(.system(size: 12))
                }
                if pkgs.contains(where: { $0.isDeprecated }) {
                    Label(String(localized: "Deprecated packages may stop working or be removed from Homebrew."), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                DisclosureGroup(String(localized: "Options"), isExpanded: $showOptions) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(String(localized: "Build from source"), isOn: $options.buildFromSource)
                            .disabled(!pkgs.contains { $0.kind == .formula })
                        Toggle(String(localized: "Install HEAD (latest development version)"), isOn: $options.head)
                            .disabled(!pkgs.contains { $0.hasHead })
                        Toggle(String(localized: "Force (overwrite existing files)"), isOn: $options.force)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 6)
                }
                .font(.system(size: 12))
                CommandPreview(commands: planned(pkgs: pkgs, alreadyInstalled: alreadyInstalled, single: single))
            }
        } buttons: {
            Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(alreadyInstalled.count == pkgs.count ? String(localized: "Reinstall") : String(localized: "Install")) {
                model.run(planned(pkgs: pkgs, alreadyInstalled: alreadyInstalled, single: single))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
        }
        .onAppear { if NSEvent.modifierFlags.contains(.option) { showOptions = true } }
    }

    /// Exactly what Install runs (shown above the button).
    private func planned(pkgs: [Package], alreadyInstalled: [Package], single: Package?) -> [BrewCommand] {
        if let v = chosenVersion, let p = single, v != p.token {
            return model.installCommands([Package.id(.formula, v)], options: options)
        }
        if alreadyInstalled.count == pkgs.count { return pkgs.compactMap { model.reinstallCommand($0.id) } }
        return model.installCommands(ids, options: options)
    }
}

// MARK: Uninstall

struct UninstallSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ignoreDeps = false

    var body: some View {
        let p = model.package(packageID) ?? model.installed[packageID].map(model.packageOrStub)
        let dependents = model.dependents(of: packageID)
        SheetChrome(title: String(localized: "Uninstall \(p?.token ?? packageID)?"),
                    subtitle: String(localized: "Removes the package. Its settings and data stay on your Mac.")) {
            VStack(alignment: .leading, spacing: 12) {
                levelsExplainer
                CommandPreview(commands: [model.uninstallCommand(packageID, ignoreDependencies: ignoreDeps)].compactMap { $0 })
                if !dependents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "Other installed packages depend on it:"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.system(size: 13, weight: .semibold))
                        Text(dependents.joined(separator: ", ")).font(.system(size: 12, design: .monospaced))
                        Toggle(String(localized: "Uninstall anyway (--ignore-dependencies); these may stop working"), isOn: $ignoreDeps)
                            .toggleStyle(.checkbox).font(.system(size: 12))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                }
            }
        } buttons: {
            Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(String(localized: "Remove Completely")) {
                model.pendingSheet = .removeCompletely(packageID)
            }
            Button(String(localized: "Uninstall"), role: .destructive) {
                model.uninstall(packageID, ignoreDependencies: ignoreDeps)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!dependents.isEmpty && !ignoreDeps)
        }
    }

    /// Localized strings with **bold** markers, rendered (Text(String) shows them literally).
    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    private var levelsExplainer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.markdown(String(localized: "**Uninstall** — remove the package only."))).font(.system(size: 12))
            Text(Self.markdown(String(localized: "**Remove completely** — also delete settings, caches and leftover files (you'll see every file first)."))).font(.system(size: 12))
            Text(Self.markdown(String(localized: "**Clean up** — afterwards, remove dependencies nothing else needs."))).font(.system(size: 12))
        }
        .foregroundStyle(Theme.text2)
    }
}

// MARK: Remove completely

struct RemoveCompletelySheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("deletePermanently") private var deletePermanently = false
    @State private var items: [RemovalItem] = []
    @State private var loading = true
    @State private var ignoreDeps = false

    var body: some View {
        let p = model.package(packageID) ?? model.installed[packageID].map(model.packageOrStub)
        let isCask = p?.kind == .cask
        let dependents = model.dependents(of: packageID)
        SheetChrome(title: String(localized: "Remove \(p?.token ?? packageID) completely?"),
                    subtitle: isCask
                        ? String(localized: "Uninstalls the app and deletes the files below. Nothing else is touched.")
                        : String(localized: "Uninstalls every installed version, then deletes the leftover files you select.")) {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    ProgressView(String(localized: "Looking for leftover files…")).controlSize(.small)
                } else if items.isEmpty {
                    Label(String(localized: "No leftover files found on disk."), systemImage: "checkmark.circle").foregroundStyle(Theme.text2)
                } else {
                    HStack {
                        Text(String(localized: "\(items.filter(\.isSelected).count) of \(items.count) items · \(items.filter(\.isSelected).reduce(0) { $0 + $1.size }.byteString)"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button(items.allSatisfy(\.isSelected) ? String(localized: "Select None") : String(localized: "Select All")) {
                            let all = items.allSatisfy(\.isSelected)
                            for i in items.indices { items[i].isSelected = !all }
                        }
                        .buttonStyle(.link).font(.system(size: 12))
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach($items) { $item in
                                Toggle(isOn: $item.isSelected) {
                                    HStack {
                                        Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(item.size.byteString).font(.system(size: 11)).foregroundStyle(Theme.text2)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chip))
                }
                if !dependents.isEmpty {
                    Toggle(String(localized: "Ignore dependents (\(dependents.joined(separator: ", ")))"), isOn: $ignoreDeps)
                        .toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(.orange)
                }
                Toggle(String(localized: "Delete permanently instead of moving to Trash"), isOn: $deletePermanently)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                if !loading {
                    let plan = removalPlan(isCask: isCask)
                    CommandPreview(commands: [plan.command].compactMap { $0 },
                                   note: plan.files.isEmpty ? nil
                                       : (deletePermanently ? String(localized: "Then deletes the \(plan.files.count) checked items permanently.")
                                                            : String(localized: "Then moves the \(plan.files.count) checked items to the Trash.")))
                }
            }
        } buttons: {
            Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(String(localized: "Remove"), role: .destructive) {
                perform(isCask: isCask)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(loading || (!dependents.isEmpty && !ignoreDeps))
        }
        .task {
            items = isCask ? await model.zapItems(for: packageID) : await model.leftoverItems(for: packageID)
            loading = false
        }
    }

    /// The user only ever loses files they saw and kept checked. For casks with everything
    /// checked and Trash mode, `brew --zap` does it (it also handles launchctl and pkg receipts);
    /// otherwise brew uninstalls and Brewlight removes exactly the checked paths.
    private func removalPlan(isCask: Bool) -> (command: BrewCommand?, files: [RemovalItem]) {
        let selected = items.filter(\.isSelected)
        if isCask && selected.count == items.count && !deletePermanently && !items.isEmpty {
            return (model.uninstallCommand(packageID, ignoreDependencies: ignoreDeps, zap: true), [])
        }
        return (model.uninstallCommand(packageID, ignoreDependencies: ignoreDeps, allVersions: true), selected)
    }

    private func perform(isCask: Bool) {
        let plan = removalPlan(isCask: isCask)
        let ops = model.run([plan.command].compactMap { $0 })
        if !plan.files.isEmpty, let uninstall = ops.first {
            // Delete the checked files only if the uninstall itself succeeded, and only wait
            // for that one operation — nothing else the user queued afterwards.
            let toRemove = plan.files
            Task { @MainActor in
                await uninstall.waitUntilFinished()
                if uninstall.state == .succeeded { model.remove(toRemove) }
            }
        }
        model.toast(String(localized: "Tip: Maintenance → Remove unused dependencies cleans up what's left."))
    }
}

// MARK: Autoremove

struct AutoremoveSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String]?

    var body: some View {
        SheetChrome(title: String(localized: "Remove unused dependencies?"),
                    subtitle: String(localized: "These were installed as dependencies and nothing installed needs them any more.")) {
            if let names {
                if names.isEmpty {
                    Label(String(localized: "Nothing to remove."), systemImage: "checkmark.circle").foregroundStyle(Theme.text2)
                } else {
                    ScrollView {
                        Text(names.joined(separator: "\n")).font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chip))
                }
            } else {
                ProgressView(String(localized: "Asking Homebrew (brew autoremove --dry-run)…")).controlSize(.small)
            }
            if names?.isEmpty == false { CommandPreview(commands: [BrewCommand("", ["autoremove"])]) }
        } buttons: {
            Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(String(localized: "Remove \(names?.count ?? 0)"), role: .destructive) { model.autoremove(); dismiss() }
                .help("brew autoremove")
                .keyboardShortcut(.defaultAction)
                .disabled((names ?? []).isEmpty)
        }
        .task {
            guard let runner = model.runner else { names = []; return }
            if AppInfo.isDemo {
                names = model.graph.orphans(installed: model.installedFormulaNames, requested: model.requestedFormulaNames)
                return
            }
            let r = await runner.output(["autoremove", "--dry-run"])
            names = MaintenanceParsers.autoremove(r.stdout + "\n" + r.stderr)
        }
    }
}

// MARK: Add tap

struct AddTapSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        SheetChrome(title: String(localized: "Add a tap"), subtitle: String(localized: "Taps are extra package repositories, usually on GitHub.")) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(String(localized: "user/repo"), text: $name).textFieldStyle(.roundedBorder)
                TextField(String(localized: "Git URL (optional, for non-GitHub taps)"), text: $url).textFieldStyle(.roundedBorder)
                Label(String(localized: "Third-party taps are not reviewed by Homebrew. Their formulae run code on your Mac when installed — only add taps you trust."),
                      systemImage: "exclamationmark.shield")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
        } buttons: {
            Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(String(localized: "Add Tap")) {
                model.addTap(url.isEmpty ? name : "\(name) \(url)")
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!BrewTap.isValidName(name))
        }
    }
}

// MARK: Why installed

struct WhyInstalledSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let name = model.package(packageID)?.token ?? packageID
        let paths = model.graph.whyInstalled(name, installed: model.installedFormulaNames, requested: model.requestedFormulaNames)
        SheetChrome(title: String(localized: "Why is \(name) installed?")) {
            if paths.isEmpty {
                Text(String(localized: "Nothing you installed needs \(name). It can probably be removed with “Remove unused dependencies”."))
                    .foregroundStyle(Theme.text2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        Text(path.joined(separator: "  →  ")).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        } buttons: {
            Button(String(localized: "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}

/// "Will run" with the exact command lines, so nothing Brewlight does is hidden.
struct CommandPreview: View {
    let commands: [BrewCommand]
    var note: String?

    var body: some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(commands.count == 1 ? String(localized: "Will run") : String(localized: "Will run, in order"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                ForEach(commands, id: \.self) { CommandLineBox(command: $0.display) }
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(Theme.text2) }
            }
        }
    }
}
