import SwiftUI

/// Other installed versions of the same software, and which one is on PATH.
struct VersionsSection: View {
    let package: Package
    @Environment(AppModel.self) private var model

    var body: some View {
        let family = model.versionFamily(of: package)
        let inst = model.installed[package.id]
        if !family.isEmpty || (inst?.versions.count ?? 0) > 1 {
            DetailSection(title: String(localized: "Versions")) {
                if !family.isEmpty {
                    Text(String(localized: "Installed side by side. The linked one provides the commands on your PATH (e.g. \(commandHint))."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 6) {
                        ForEach(family, id: \.token) { member in
                            HStack(spacing: 10) {
                                Image(systemName: member.linkedIntoPrefix == true ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(member.linkedIntoPrefix == true ? Theme.success : Theme.text3)
                                Text(member.token).font(.system(size: 12, weight: member.token == package.token ? .semibold : .regular, design: .monospaced))
                                Text(member.currentVersion).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text3)
                                Spacer()
                                Text(member.linkedIntoPrefix == true ? String(localized: "linked") : String(localized: "not linked"))
                                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
                                if !(member.linkedIntoPrefix == true && family.filter({ $0.linkedIntoPrefix == true }).count == 1) {
                                    Button(String(localized: "Make Default…")) { model.pendingSheet = .switchVersion(Package.id(.formula, member.token)) }
                                        .buttonStyle(.link).font(.system(size: 12))
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chip))
                }
                if let inst, inst.versions.count > 1 {
                    HStack {
                        Text(String(localized: "Kegs of \(inst.token): \(inst.versions.joined(separator: ", "))"))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text2)
                        Spacer()
                        Button(String(localized: "Remove Old Versions…")) { model.pendingSheet = .removeOldVersions(package.id) }
                            .buttonStyle(.link).font(.system(size: 12))
                    }
                }
            }
        }
    }

    private var commandHint: String {
        let base = package.token.split(separator: "@").first.map(String.init) ?? package.token
        return base == "python" ? "python3" : base
    }
}

/// How much of Homebrew's download cache this package uses, with a way to clear just that.
struct CacheRow: View {
    let package: Package
    @Environment(AppModel.self) private var model
    @State private var entries: [PackageCache.Entry]?

    var body: some View {
        Group {
            if let entries, !entries.isEmpty {
                DetailSection(title: String(localized: "Download Cache")) {
                    HStack {
                        Text(String(localized: "\(PackageCache.totalSize(entries).byteString) in \(entries.count) cached downloads"))
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Spacer()
                        Button(String(localized: "Clear…")) { model.pendingSheet = .clearCache(package.id) }
                            .buttonStyle(.link).font(.system(size: 12))
                    }
                    Text(String(localized: "Installers Homebrew keeps so reinstalls are fast. Safe to delete; they're downloaded again if needed."))
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            }
        }
        .task(id: "\(package.id)|\(model.operations.operations.count)") { entries = await model.cacheEntries(for: package.id) }
    }
}

// MARK: Sheets

struct SwitchVersionSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let commands = model.switchVersionCommands(to: packageID)
        let name = model.package(packageID)?.token ?? packageID
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Make \(name) the default?")).font(.system(size: 20, weight: .bold))
            Text(String(localized: "Its commands will be the ones on your PATH. The other versions stay installed and keep working by their full path."))
                .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            CommandPreview(commands: commands)
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Make Default")) { model.run(commands); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
            }
        }
        .padding(24).frame(width: 540)
    }
}

struct RemoveOldVersionsSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let inst = model.installed[packageID]
        let command = model.removeOldVersionsCommand(packageID)
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Remove old versions of \(inst?.token ?? packageID)?")).font(.system(size: 20, weight: .bold))
            if let inst {
                Text(String(localized: "Keeps \(inst.currentVersion) and removes \(inst.versions.filter { $0 != inst.currentVersion }.joined(separator: ", ")), plus its outdated downloads."))
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            CommandPreview(commands: [command].compactMap { $0 })
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Remove"), role: .destructive) { model.run([command].compactMap { $0 }); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(command == nil)
            }
        }
        .padding(24).frame(width: 540)
    }
}

struct ClearCacheSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PackageCache.Entry]?

    var body: some View {
        let name = model.package(packageID)?.token ?? packageID
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Clear cached downloads for \(name)?")).font(.system(size: 20, weight: .bold))
            Text(String(localized: "These files are deleted permanently (not moved to the Trash); Homebrew downloads them again if it needs them. The installed package isn't touched."))
                .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            if let entries {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries, id: \.link) { e in
                            HStack {
                                Text((e.file ?? e.link).lastPathComponent).font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(e.size.byteString).font(.system(size: 11)).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chip))
            } else {
                ProgressView().controlSize(.small)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Delete \(PackageCache.totalSize(entries ?? []).byteString)"), role: .destructive) {
                    if let entries { model.clearCache(entries, for: name) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries?.isEmpty ?? true)
            }
        }
        .padding(24).frame(width: 560)
        .task { entries = await model.cacheEntries(for: packageID) }
    }
}
