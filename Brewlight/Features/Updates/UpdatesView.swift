import SwiftUI

struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("greedyCasks") private var greedy = false
    @AppStorage("developerMode") private var developerMode = false
    @State private var unchecked: Set<String> = []

    var body: some View {
        let all = model.visibleOutdated.values.sorted { $0.token < $1.token }
        let active = all.filter { !$0.pinned }
        let pinned = all.filter(\.pinned)
        let selected = active.filter { !unchecked.contains($0.id) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Updates"), subtitle: subtitle(count: active.count)) {
                    HStack(spacing: 10) {
                        Button(model.isCheckingOutdated ? String(localized: "Checking…") : String(localized: "Check Again")) {
                            Task { await model.refreshOutdated(confirmWithBrew: true) }
                        }
                        .buttonStyle(ChipButtonStyle(height: 38))
                        .disabled(model.isCheckingOutdated)
                        .help(String(localized: "Compare installed versions with Homebrew's index"))
                        Button {
                            if selected.count == active.count { model.upgradeAll() } else { model.upgrade(selected.map(\.id)) }
                        } label: {
                            HStack(spacing: 8) {
                                Text(selected.count == active.count ? String(localized: "Upgrade All") : String(localized: "Upgrade Selected"))
                                Text("\(selected.count)").font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 7).padding(.vertical, 1)
                                    .background(Capsule().fill(.black.opacity(0.12)))
                            }
                        }
                        .buttonStyle(PrimaryPillButtonStyle(height: 38))
                        .disabled(selected.isEmpty)
                        .keyboardShortcut("u", modifiers: [.command, .shift])
                    }
                }

                if developerMode && !selected.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.upgradeCommands(selected.map(\.id)), id: \.self) { CommandLineBox(command: $0.display) }
                    }
                }
                HStack(spacing: 16) {
                    Toggle(String(localized: "Include casks that update themselves"), isOn: $greedy)
                        .toggleStyle(.checkbox)
                        .onChange(of: greedy) { Task { await model.refreshOutdated(confirmWithBrew: true) } }
                    Spacer()
                    Text(String(localized: "“Update” refreshes Homebrew's index (⌘R). “Upgrade” installs newer versions."))
                        .foregroundStyle(Theme.text3)
                }
                .font(.system(size: 12))

                if all.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal", title: String(localized: "Everything is up to date"),
                                   message: model.outdatedCheckedAt.map { String(localized: "Checked \($0.relative).") } ?? String(localized: "Checking for updates…"))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    table(active: active, pinned: pinned)
                }

                let deprecated = model.deprecatedInstalled
                if !deprecated.isEmpty { deprecatedSection(deprecated) }

                let broken = model.brokenEntries
                if !broken.isEmpty { brokenSection(broken) }

                if !model.userData.skipped.isEmpty {
                    skippedSection
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.list)
    }

    private func subtitle(count: Int) -> String {
        let checked = model.outdatedCheckedAt.map { String(localized: "checked \($0.relative)") } ?? String(localized: "checking…")
        return count == 1
            ? String(localized: "1 update available · \(checked)")
            : String(localized: "\(count) updates available · \(checked)")
    }

    private let columns = [GridItem(.fixed(28)), GridItem(.flexible(minimum: 200)), GridItem(.flexible(minimum: 160)), GridItem(.fixed(120))]

    private func table(active: [OutdatedInfo], pinned: [OutdatedInfo]) -> some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: 16) {
                checkbox(isOn: unchecked.isEmpty) {
                    unchecked = unchecked.isEmpty ? Set(active.map(\.id)) : []
                }
                .frame(width: 28, alignment: .leading)
                Text(String(localized: "Package")).frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "Version")).frame(width: 220, alignment: .leading)
                Spacer().frame(width: 120)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }

            ForEach(active) { info in
                UpdateRow(info: info, isOn: !unchecked.contains(info.id)) {
                    if unchecked.contains(info.id) { unchecked.remove(info.id) } else { unchecked.insert(info.id) }
                }
            }
            ForEach(pinned) { info in
                HStack(spacing: 10) {
                    Image(systemName: "pin").font(.system(size: 12))
                    Text(pinnedMessage(info))
                    Spacer()
                    Button(String(localized: "Unpin")) { model.pin(info.id, false) }.buttonStyle(.link)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 20)
                .frame(height: 46)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func pinnedMessage(_ info: OutdatedInfo) -> AttributedString {
        var name = AttributedString(info.token)
        name.font = .system(size: 12, weight: .semibold)
        name.foregroundColor = Theme.text
        return name + AttributedString(String(localized: " is pinned at \(info.installed) — \(info.available) available. Unpin to include it in Upgrade All."))
    }

    /// Installed packages Homebrew has deprecated or disabled, with what to do about each.
    private func deprecatedSection(_ pkgs: [Package]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Deprecated or disabled (\(pkgs.count))")).font(.system(size: 15, weight: .semibold))
                Text(String(localized: "Homebrew no longer maintains these. They keep working for now, but won't get fixes and may be removed."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            VStack(spacing: 0) {
                ForEach(pkgs) { p in DeprecatedRow(package: p) }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }

    /// Installed packages that can no longer be upgraded cleanly: removed from Homebrew, or
    /// deleted by hand while brew still tracks them. Uninstalling clears each problem.
    private func brokenSection(_ issues: [(inst: InstalledPackage, issue: CleanupIssues.Issue)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Needs attention (\(issues.count))")).font(.system(size: 15, weight: .semibold))
                Text(String(localized: "These entries are broken or stale. Uninstall them so upgrades run cleanly."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            VStack(spacing: 0) {
                ForEach(issues, id: \.inst.id) { issue in
                    BrokenRow(item: issue)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }

    private var skippedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Skipped versions")).font(.system(size: 13, weight: .semibold))
            ForEach(model.userData.skipped.sorted(by: { $0.key < $1.key }), id: \.key) { id, version in
                HStack {
                    Text("\(model.package(id)?.token ?? id) \(version)").font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button(String(localized: "Stop Skipping")) { model.userData.unskip(id) }.buttonStyle(.link).font(.system(size: 12))
                }
            }
        }
    }
}

@MainActor func checkbox(isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(isOn ? Theme.accent : .clear)
            RoundedRectangle(cornerRadius: 5).strokeBorder(isOn ? .clear : Theme.text3, lineWidth: 1)
            if isOn { Text("✓").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accentInk) }
        }
        .frame(width: 16, height: 16)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
}

struct UpdateRow: View {
    let info: OutdatedInfo
    let isOn: Bool
    let toggle: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.package(info.id)
        let op = model.operations.active.first { $0.packages.contains(info.token) }
        HStack(spacing: 16) {
            checkbox(isOn: isOn, action: toggle).frame(width: 28, alignment: .leading)
                .accessibilityLabel(String(localized: "Include \(info.token)"))
            HStack(spacing: 12) {
                if let p { PackageIcon(package: p, size: 34, appPath: model.installed[info.id]?.appPaths.first) }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(info.token).font(.system(size: 13, weight: .semibold))
                        KindBadge(kind: info.kind)
                    }
                    Text(note(p)).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.reveal(info.id) }
            HStack(spacing: 8) {
                Text(info.installed).foregroundStyle(Theme.text2)
                Text("→").foregroundStyle(Theme.text3)
                Text(info.available).foregroundStyle(Theme.accentText).fontWeight(.bold)
            }
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .frame(width: 220, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(info.installed) to \(info.available)"))
            HStack {
                Spacer()
                if let op {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(op.phase.label)
                            Spacer()
                            if let pct = op.percent { Text("\(Int(pct * 100))%").monospacedDigit() }
                        }
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                        ProgressView(value: op.percent ?? 0).progressViewStyle(.linear).tint(Theme.accent)
                    }
                    .frame(width: 110)
                } else {
                    RowActionButton(title: String(localized: "Upgrade")) { model.upgrade([info.id]) }
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .contextMenu {
            if let p { PackageContextMenu(package: p) }
            Button(String(localized: "Skip \(info.available)")) { model.userData.skip(info.id, version: info.available) }
            if let url = p?.releasesURL { Button(String(localized: "Release Notes")) { NSWorkspace.shared.open(url) } }
        }
    }

    private func note(_ p: Package?) -> String {
        if let p, p.kind == .cask, p.autoUpdates { return String(localized: "Updates itself — upgrading through Homebrew anyway") }
        return p?.desc ?? ""
    }
}

struct DeprecatedRow: View {
    let package: Package
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = package
        let replacement = p.replacement.flatMap { model.package(named: $0, kind: p.kind) ?? model.package(named: $0) }
        HStack(spacing: 14) {
            PackageIcon(package: p, size: 34, appPath: model.installed[p.id]?.appPaths.first)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.token).font(.system(size: 13, weight: .semibold))
                    KindBadge(kind: p.kind)
                    Text(p.isDisabled ? String(localized: "disabled") : String(localized: "deprecated"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.warning)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.warning.opacity(0.14)))
                }
                Text(reasonText(p, replacement: replacement)).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
            }
            Spacer()
            if let r = replacement {
                if model.isInstalled(r.id) {
                    Label(String(localized: "\(r.token) installed"), systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(Theme.success)
                } else {
                    RowActionButton(title: String(localized: "Install \(r.token)")) { model.pendingSheet = .install([r.id]) }
                        .help(r.installCommand)
                }
            }
            RowActionButton(title: String(localized: "Uninstall"), prominent: false) { model.pendingSheet = .uninstall(p.id) }
            Button { model.reveal(p.id) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(Theme.text3)
                .accessibilityLabel(String(localized: "Show \(p.token)"))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func reasonText(_ p: Package, replacement: Package?) -> String {
        let reason = (p.disableReason ?? p.deprecationReason ?? "").capitalizedFirst
        if let r = replacement { return String(localized: "\(reason). Homebrew suggests \(r.token) instead.") }
        return String(localized: "\(reason). Homebrew doesn't name a replacement.")
    }
}

struct BrokenRow: View {
    let item: (inst: InstalledPackage, issue: CleanupIssues.Issue)
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            PackageIcon(package: package, size: 34, appPath: model.installed[item.inst.id]?.appPaths.first)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.inst.token).font(.system(size: 13, weight: .semibold))
                    KindBadge(kind: item.inst.kind)
                    Text(reason).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.red)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.red.opacity(0.14)))
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2)
            }
            Spacer()
            RowActionButton(title: String(localized: "Uninstall"), danger: true) {
                model.pendingSheet = .uninstall(item.inst.id)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private var package: Package {
        model.package(item.inst.id) ?? model.packageOrStub(item.inst)
    }

    private var reason: String {
        item.issue == .removedFromHomebrew
            ? String(localized: "no longer in Homebrew")
            : String(localized: "app deleted outside brew")
    }

    private var detail: String {
        switch item.issue {
        case .removedFromHomebrew:
            String(localized: "Not in any tap anymore, so `brew upgrade` fails on it. Uninstall to clear the entry.")
        case .appDeletedOutsideBrew:
            String(localized: "The app was deleted outside Homebrew (Trash or ⌘⌫), so brew still thinks it's installed. Uninstall to remove the stale entry.")
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
