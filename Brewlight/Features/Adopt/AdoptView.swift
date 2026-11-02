import SwiftUI

/// Apps you installed yourself that a Homebrew cask can take over, so Homebrew keeps them updated.
struct AdoptView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: [AdoptableApp]?

    var body: some View {
        let apps = model.adoptable
        let ready = model.adoptableReady
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Adopt Apps"),
                             subtitle: String(localized: "Apps you installed yourself that Homebrew can keep up to date")) {
                    HStack(spacing: 10) {
                        Button(model.isScanningAdoptable ? String(localized: "Scanning…") : String(localized: "Scan Again")) {
                            Task { await model.scanAdoptable() }
                        }
                        .buttonStyle(ChipButtonStyle(height: 38))
                        .disabled(model.isScanningAdoptable)
                        Button(String(localized: "Adopt All Ready (\(ready.count))")) { confirming = ready }
                            .buttonStyle(PrimaryPillButtonStyle(height: 38))
                            .disabled(ready.isEmpty)
                    }
                }
                Text(String(localized: "Adopting hands an app to Homebrew without moving or reinstalling it, using “brew install --cask --adopt”. From then on it shows up in Installed and updates with everything else. If Homebrew can't adopt an app, it stops and leaves the app as it was."))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)

                if apps.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal",
                                   title: model.adoptableScannedAt == nil ? String(localized: "Looking for apps…") : String(localized: "Nothing to adopt"),
                                   message: String(localized: "Every app in Applications that has a Homebrew cask is already managed by Homebrew."))
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(spacing: 0) {
                        ForEach(apps) { app in
                            AdoptRow(app: app) { confirming = [app] }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.separator))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 40)
        }
        .background(Theme.list)
        .task { if model.adoptableScannedAt == nil { await model.scanAdoptable() } }
        .sheet(item: Binding(get: { confirming.map(AdoptRequest.init) }, set: { confirming = $0?.apps })) { req in
            AdoptConfirmSheet(apps: req.apps)
        }
    }
}

private struct AdoptRequest: Identifiable {
    let apps: [AdoptableApp]
    var id: String { apps.map(\.id).joined(separator: "|") }
}

struct AdoptRow: View {
    let app: AdoptableApp
    let adopt: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    Text("→ \(app.token)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.accentText)
                }
                Text(versionLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2)
            }
            Spacer()
            statusChip
            if app.status == .appStore {
                Button(String(localized: "Adopt Anyway…"), action: adopt).buttonStyle(.link).font(.system(size: 12))
            } else {
                RowActionButton(title: String(localized: "Adopt"), action: adopt)
                    .help("brew install --cask --adopt \(app.token)")
            }
            Button { model.reveal(Package.id(.cask, app.token)) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(Theme.text3)
                .accessibilityLabel(String(localized: "Show the \(app.token) cask"))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private var versionLine: String {
        String(localized: "yours \(app.appVersion ?? "unknown") · Homebrew \(app.caskVersion)")
    }

    @ViewBuilder private var statusChip: some View {
        switch app.status {
        case .ready:
            chip(String(localized: "Ready"), Theme.success)
        case .versionDiffers:
            chip(String(localized: "Version differs"), Theme.warning)
                .help(String(localized: "Your copy is a different version from Homebrew's. Adopting may fail; nothing changes if it does."))
        case .appStore:
            chip(String(localized: "From the App Store"), Theme.text2)
                .help(String(localized: "Bought from the App Store. Homebrew would replace it with the developer's download on the next update, which can lose an App Store licence. Not recommended for paid apps."))
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct AdoptConfirmSheet: View {
    let apps: [AdoptableApp]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let commands = model.adoptCommands(apps)
        VStack(alignment: .leading, spacing: 14) {
            Text(apps.count == 1 ? String(localized: "Adopt \(apps[0].name)?") : String(localized: "Adopt \(apps.count) apps?"))
                .font(.system(size: 20, weight: .bold))
            Text(String(localized: "Homebrew takes over the apps where they are; nothing is moved or reinstalled. Afterwards they update through Homebrew (Updates, Upgrade All)."))
                .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            if apps.contains(where: { $0.status == .appStore }) {
                Label(String(localized: "Includes an App Store app. Homebrew will replace it with the developer's download when it next updates."), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            ScrollView { CommandPreview(commands: commands) }.frame(maxHeight: 240)
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(apps.count == 1 ? String(localized: "Adopt") : String(localized: "Adopt \(apps.count)")) {
                    model.run(commands)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
