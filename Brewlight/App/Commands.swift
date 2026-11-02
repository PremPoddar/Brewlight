import SwiftUI

struct BrewlightCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") }
        let _ = AppDelegate.openAboutWindow = { [openWindow] in openWindow(id: "about") }
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About \(AppInfo.name)")) { openWindow(id: "about") }
            Button(String(localized: "Check for Updates…")) {
                Task { await model.updater.check(runner: model.runner, operations: model.operations) }
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .textEditing) {
            Button(String(localized: "Search")) { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                .keyboardShortcut("f")
            Button(String(localized: "Command Palette")) { model.showPalette.toggle() }
                .keyboardShortcut("k")
        }

        CommandMenu(String(localized: "Packages")) {
            Button(String(localized: "Update Homebrew (refresh metadata)")) { model.updateHomebrew() }
                .keyboardShortcut("r")
            Button(String(localized: "Upgrade All")) { model.upgradeAll() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Divider()
            Button(String(localized: "Install Selected")) {
                if let id = model.selectedPackageID, !model.isInstalled(id) { model.pendingSheet = .install([id]) }
            }
            .keyboardShortcut("i")
            .disabled(model.selectedPackageID.map(model.isInstalled) ?? true)
            Button(String(localized: "Uninstall Selected")) {
                if let id = model.selectedPackageID { model.pendingSheet = .uninstall(id) }
            }
            .keyboardShortcut(.delete)
            .disabled(!(model.selectedPackageID.map(model.isInstalled) ?? false))
            Button(String(localized: "Remove Completely…")) {
                if let id = model.selectedPackageID { model.pendingSheet = .removeCompletely(id) }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(!(model.selectedPackageID.map(model.isInstalled) ?? false))
            Button(String(localized: "Open in New Window")) {
                if let id = model.selectedPackageID { openWindow(id: "package", value: id) }
            }
            .keyboardShortcut("o")
            .disabled(model.selectedPackageID == nil)
            Divider()
            Button(String(localized: "Remove Unused Dependencies…")) { model.pendingSheet = .autoremove }
        }

        CommandGroup(after: .sidebar) {
            ForEach(Array(SidebarItem.numbered.enumerated()), id: \.offset) { i, item in
                Button(item.title) { model.sidebar = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
            Divider()
            Button(model.showActivity ? String(localized: "Hide Activity") : String(localized: "Show Activity")) {
                model.showActivity.toggle()
            }
            .keyboardShortcut("l")
            Button(String(localized: "Back")) { model.goBack() }
                .keyboardShortcut("[")
                .disabled(!model.canGoBack)
            Button(String(localized: "Forward")) { model.goForward() }
                .keyboardShortcut("]")
                .disabled(!model.canGoForward)
        }

        CommandMenu(String(localized: "Debug")) {
            Toggle(String(localized: "Show Performance HUD"), isOn: Binding(get: { model.showPerfHUD }, set: { model.showPerfHUD = $0 }))
            Button(String(localized: "Reload Catalog")) { Task { await model.refreshCatalog(force: true) } }
            Button(String(localized: "Rescan Installed Packages")) { Task { await model.rescanInstalled() } }
        }

        CommandGroup(replacing: .help) {
            Button(String(localized: "Report an Issue…")) { NSWorkspace.shared.open(AppInfo.issuesURL) }
            Button(String(localized: "Homebrew Documentation")) { NSWorkspace.shared.open(URL(string: "https://docs.brew.sh")!) }
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("BrewlightFocusSearch")
}
