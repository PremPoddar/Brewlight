import SwiftUI
import UniformTypeIdentifiers

struct BrewfileView: View {
    @Environment(AppModel.self) private var model
    @State private var sections: Set<Brewfile.Section> = [.tap, .brew, .cask, .mas, .vscode]
    @State private var exporting = false
    @State private var includeUserData = true
    @AppStorage("syncBrewfileToICloud") private var syncICloud = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Brewfile"), subtitle: String(localized: "Back up and restore everything you installed"))
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Export"), systemImage: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                        ForEach(Brewfile.Section.allCases) { s in
                            Toggle(s.label, isOn: Binding(get: { sections.contains(s) }, set: { if $0 { sections.insert(s) } else { sections.remove(s) } }))
                        }
                        Toggle(String(localized: "Include my tags as comments"), isOn: $includeUserData)
                        Toggle(String(localized: "Keep a copy in iCloud Drive automatically"), isOn: $syncICloud)
                        Button(exporting ? String(localized: "Exporting…") : String(localized: "Export Brewfile…")) { Task { await export() } }
                            .buttonStyle(.glassProminent)
                            .disabled(exporting || sections.isEmpty)
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator))

                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Import"), systemImage: "square.and.arrow.down").font(.system(size: 14, weight: .semibold))
                        Text(String(localized: "Pick a Brewfile (or drop one on the window or Dock icon). You'll see what's new, what's already here, and what's extra before anything installs."))
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Button(String(localized: "Choose Brewfile…")) {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url { model.pendingSheet = .brewfileImport(url) }
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.separator))
                }
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
    }

    private func export() async {
        guard let runner = model.runner else { return }
        exporting = true
        defer { exporting = false }
        let tmp = FileManager.default.temporaryDirectory.appending(path: "Brewfile-\(UUID().uuidString)")
        let r = await runner.output(["bundle", "dump", "--describe", "--force", "--file=\(tmp.path)"])
        var text = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: tmp)
        if text.isEmpty && AppInfo.isDemo {
            text = model.installed.values.sorted { $0.token < $1.token }.map { "\($0.kind == .cask ? "cask" : "brew") \"\($0.token)\"" }.joined(separator: "\n")
        }
        guard !text.isEmpty else { model.toast(r.stderr.isEmpty ? String(localized: "Export failed") : r.stderr, error: true); return }
        text = Brewfile.filter(text, keep: sections)
        if includeUserData {
            var lines: [String] = ["# Exported by \(AppInfo.name) on \(Date.now.formatted(date: .abbreviated, time: .shortened))"]
            for tag in model.userData.tags where !tag.packageIDs.isEmpty {
                lines.append("# tag \(tag.name): " + tag.packageIDs.compactMap { model.package($0)?.token }.joined(separator: ", "))
            }
            text = lines.joined(separator: "\n") + "\n\n" + text
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brewfile"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            if syncICloud { Self.copyToICloud(text) }
            model.toast(String(localized: "Brewfile saved"))
        } catch {
            model.toast(error.localizedDescription, error: true)
        }
    }

    static func copyToICloud(_ text: String) {
        let dir = URL.homeDirectory.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Brewlight")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: dir.appending(path: "Brewfile"), atomically: true, encoding: .utf8)
    }
}

struct BrewfileImportSheet: View {
    let url: URL
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var brewfile: Brewfile?
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Import \(url.lastPathComponent)")).font(.system(size: 20, weight: .bold))
            if let brewfile {
                let diff = brewfile.diff(installedFormulae: model.installedFormulaNames,
                                         installedCasks: Set(model.installed.values.filter { $0.kind == .cask }.map(\.token)),
                                         taps: Set(model.taps.map { $0.name.lowercased() }),
                                         requestedFormulae: model.requestedFormulaNames)
                List {
                    Section(String(localized: "Will install (\(diff.toInstall.count))")) {
                        ForEach(diff.toInstall) { e in
                            Toggle(isOn: Binding(get: { selected.contains(e.id) }, set: { if $0 { selected.insert(e.id) } else { selected.remove(e.id) } })) {
                                HStack { Text(e.name).font(.system(size: 12, design: .monospaced)); Text(e.section.rawValue).foregroundStyle(Theme.text3).font(.system(size: 11)) }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    Section(String(localized: "Already on this Mac (\(diff.alreadyPresent.count))")) {
                        ForEach(diff.alreadyPresent) { Text($0.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text2) }
                    }
                    Section(String(localized: "On this Mac but not in the file (\(diff.extra.count))")) {
                        Text(diff.extra.joined(separator: ", ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text3)
                    }
                }
                .frame(height: 360)
                HStack {
                    Spacer()
                    Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(String(localized: "Install \(selected.count)")) {
                        install(diff.toInstall.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(selected.isEmpty)
                }
                .onAppear { selected = Set(diff.toInstall.map(\.id)) }
            } else {
                Text(String(localized: "This file doesn't look like a Brewfile.")).foregroundStyle(Theme.text2)
                HStack { Spacer(); Button(String(localized: "Close")) { dismiss() } }
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let b = Brewfile.parse(text)
                brewfile = b.entries.isEmpty ? nil : b
            }
        }
    }

    /// Writes only the selected entries to a temporary Brewfile and runs `brew bundle install` on it.
    private func install(_ entries: [Brewfile.Entry]) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "Brewfile-import-\(UUID().uuidString.prefix(6))")
        try? Brewfile.render(entries).write(to: tmp, atomically: true, encoding: .utf8)
        model.operations.enqueue(String(localized: "Install from Brewfile (\(entries.count))"), ["bundle", "install", "--file=\(tmp.path)"], packages: entries.map(\.name))
        model.showActivity = true
    }
}
