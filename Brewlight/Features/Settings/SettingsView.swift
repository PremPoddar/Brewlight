import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab(String(localized: "General"), systemImage: "gearshape") { GeneralSettings() }
            Tab(String(localized: "Appearance"), systemImage: "paintpalette") { AppearanceSettings() }
            Tab(String(localized: "Updates"), systemImage: "arrow.up.circle") { UpdateSettings() }
            Tab(String(localized: "Homebrew"), systemImage: "terminal") { HomebrewSettings() }
            Tab(String(localized: "Network"), systemImage: "network") { NetworkSettingsView() }
            Tab(String(localized: "Privacy"), systemImage: "hand.raised") { PrivacySettings() }
            Tab(String(localized: "App Updates"), systemImage: "sparkles") { AppUpdateSettings() }
            Tab(String(localized: "Advanced"), systemImage: "wrench.and.screwdriver") { AdvancedSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage("dockBadge") private var dockBadge = true
    @AppStorage("confirmDestructive") private var confirm = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Toggle(String(localized: "Show update count on the Dock icon"), isOn: $dockBadge)
                .onChange(of: dockBadge) { model.updateBadges() }
            Toggle(String(localized: "Confirm before destructive actions"), isOn: $confirm)
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("listDensity") private var density = "comfortable"

    var body: some View {
        Form {
            Picker(String(localized: "Appearance"), selection: $appearance) {
                Text(String(localized: "System")).tag("system")
                Text(String(localized: "Light")).tag("light")
                Text(String(localized: "Dark")).tag("dark")
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, v in Appearance.apply(v) }
            Picker(String(localized: "List density"), selection: $density) {
                Text(String(localized: "Comfortable")).tag("comfortable")
                Text(String(localized: "Compact")).tag("compact")
            }
            Text(String(localized: "Brewlight uses its amber accent; system accent colours apply to controls."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @AppStorage("checkInterval") private var interval = "4h"
    @AppStorage("onlyOnACPower") private var acOnly = true
    @AppStorage("notifications") private var notifications = true
    @AppStorage("quietMode") private var quiet = false
    @AppStorage("greedyCasks") private var greedy = false
    @AppStorage("autoUpgrade") private var autoUpgrade = false

    var body: some View {
        Form {
            Picker(String(localized: "Check for package updates"), selection: $interval) {
                Text(String(localized: "Every hour")).tag("1h")
                Text(String(localized: "Every 4 hours")).tag("4h")
                Text(String(localized: "Daily")).tag("daily")
                Text(String(localized: "Manually")).tag("manual")
            }
            Toggle(String(localized: "Only when connected to power"), isOn: $acOnly)
            Toggle(String(localized: "Notify me about updates"), isOn: $notifications)
            Toggle(String(localized: "Quiet mode (badge only, no banners)"), isOn: $quiet).disabled(!notifications)
            Toggle(String(localized: "Include casks that update themselves (--greedy)"), isOn: $greedy)
            Section {
                Toggle(String(localized: "Upgrade automatically"), isOn: $autoUpgrade)
            } footer: {
                Text(String(localized: "Upgrades can break things: a new major version of a database or language may need migration, and running apps may be replaced while open. Leave this off unless you're comfortable fixing that."))
                    .foregroundStyle(autoUpgrade ? .orange : .secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HomebrewSettings: View {
    @AppStorage(BrewLocator.overrideKey) private var brewPath = ""
    @AppStorage("extraEnvironment") private var extraEnv = ""
    @AppStorage("developerMode") private var developerMode = false
    @Environment(AppModel.self) private var model
    @State private var analyticsOn: Bool?

    var body: some View {
        Form {
            LabeledContent(String(localized: "Detected"), value: model.env.map { "\($0.brew.path) (\($0.version))" } ?? String(localized: "Not found"))
            TextField(String(localized: "brew path override"), text: $brewPath, prompt: Text("/opt/homebrew/bin/brew"))
            Button(String(localized: "Re-detect Homebrew")) { Task { await model.retryLocating() } }
            Section(String(localized: "Extra environment variables")) {
                TextEditor(text: $extraEnv).font(.system(.body, design: .monospaced)).frame(height: 70)
                Text(String(localized: "One per line, e.g. HOMEBREW_CASK_OPTS=--appdir=~/Applications")).font(.caption).foregroundStyle(.secondary)
            }
            if let on = analyticsOn {
                Toggle(String(localized: "Share anonymous analytics with Homebrew"), isOn: Binding(get: { on }, set: { v in
                    analyticsOn = v
                    model.operations.enqueue(String(localized: "Turn analytics \(v ? "on" : "off")"), ["analytics", v ? "on" : "off"], mutating: false)
                }))
            }
            Toggle(String(localized: "Developer mode"), isOn: $developerMode)
            Text(String(localized: "Shows the exact brew command next to buttons that run one (Upgrade All, row actions). Confirmation sheets always show it."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            let r = await model.runner?.output(["analytics", "state"])
            analyticsOn = r.map { !$0.stdout.lowercased().contains("disabled") }
        }
    }
}

private struct PrivacySettings: View {
    @AppStorage("fetchIcons") private var fetchIcons = true
    @AppStorage("fetchAnalytics") private var fetchAnalytics = true
    @AppStorage("fetchGitHub") private var fetchGitHub = true

    var body: some View {
        Form {
            Toggle(String(localized: "Fetch package icons from the web"), isOn: $fetchIcons)
            Toggle(String(localized: "Fetch install statistics from formulae.brew.sh"), isOn: $fetchAnalytics)
            Toggle(String(localized: "Fetch release links from GitHub"), isOn: $fetchGitHub)
            Button(String(localized: "Clear Icon Cache")) { Task { await IconResolver.shared.clearCache() } }
            Button(String(localized: "Clear All Caches")) {
                Task { await IconResolver.shared.clearCache() }
                // Contents only: stores keep paths into this folder, deleting the folder itself
                // would make their next write fail silently until relaunch.
                if let items = try? FileManager.default.contentsOfDirectory(at: Paths.caches, includingPropertiesForKeys: nil) {
                    for item in items { try? FileManager.default.removeItem(at: item) }
                }
            }
            Text(String(localized: "Brewlight sends nothing about you anywhere. Network requests go to formulae.brew.sh, GitHub, and package homepages (for icons) only."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppUpdateSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("autoCheckAppUpdates") private var autoCheck = true

    var body: some View {
        Form {
            LabeledContent(String(localized: "Version"), value: "\(AppInfo.version) (\(AppInfo.build))")
            LabeledContent(String(localized: "Update channel"), value: model.updater.channel == .cask
                           ? String(localized: "Homebrew cask (brew upgrade --cask \(AppInfo.caskToken))")
                           : String(localized: "Direct download"))
            Toggle(String(localized: "Check for app updates automatically"), isOn: $autoCheck)
                .disabled(model.updater.channel == .cask)
            Button(String(localized: "Check for Updates…")) {
                Task { await model.updater.check(runner: model.runner, operations: model.operations) }
            }
            if let r = model.updater.lastResult { Text(r).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("deletePermanently") private var deletePermanently = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Toggle(String(localized: "Delete leftover files permanently (instead of moving to Trash)"), isOn: $deletePermanently)
            Button(String(localized: "Export App Data…")) {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "brewlight-data.json"
                if panel.runModal() == .OK, let url = panel.url, let data = try? model.userData.exportData() { try? data.write(to: url) }
            }
            Button(String(localized: "Import App Data…")) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                    do { try model.userData.importData(data) } catch { model.toast(error.localizedDescription, error: true) }
                }
            }
            Button(String(localized: "Open Logs Folder")) { NSWorkspace.shared.open(Paths.logs) }
            Button(String(localized: "Reset All Data…"), role: .destructive) { confirmReset = true }
        }
        .formStyle(.grouped)
        .confirmationDialog(String(localized: "Reset all Brewlight data?"), isPresented: $confirmReset) {
            Button(String(localized: "Reset"), role: .destructive) { model.userData.resetAll() }
        } message: {
            Text(String(localized: "Deletes tags, notes, favourites, skipped versions and history. Homebrew and your packages are not affected."))
        }
    }
}

private struct NetworkSettingsView: View {
    @AppStorage(NetworkSettings.useSystemProxyKey) private var useSystemProxy = true
    @AppStorage(NetworkSettings.mirrorKey) private var mirror = DownloadMirror.official.rawValue
    @AppStorage(NetworkSettings.customAPIKey) private var customAPI = ""
    @AppStorage(NetworkSettings.customBottlesKey) private var customBottles = ""
    @AppStorage(NetworkSettings.customGitKey) private var customGit = ""
    @State private var detected = NetworkSettings.systemProxySummary()

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Use macOS proxy settings for Homebrew"), isOn: $useSystemProxy)
                LabeledContent(String(localized: "Detected proxy"), value: detected ?? String(localized: "None"))
            } footer: {
                Text(String(localized: "Homebrew runs curl and git, which don't read macOS's proxy settings on their own. Brewlight passes them along. Variables you set under Homebrew → Extra environment variables take precedence."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(String(localized: "Download from"), selection: $mirror) {
                    ForEach(DownloadMirror.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if mirror == DownloadMirror.custom.rawValue {
                    TextField(String(localized: "API domain"), text: $customAPI, prompt: Text("https://example.com/homebrew-bottles/api"))
                    TextField(String(localized: "Bottle domain"), text: $customBottles, prompt: Text("https://example.com/homebrew-bottles"))
                    TextField(String(localized: "brew git remote"), text: $customGit, prompt: Text("https://example.com/brew.git"))
                }
                if let p = DownloadMirror(rawValue: mirror)?.preset {
                    Text("HOMEBREW_API_DOMAIN=\(p.api)\nHOMEBREW_BOTTLE_DOMAIN=\(p.bottles)\nHOMEBREW_BREW_GIT_REMOTE=\(p.git)")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Download mirror"))
            } footer: {
                Text(String(localized: "Mirrors can be much faster where GitHub is slow. They must keep up with Homebrew's current API; if installs start failing, switch back to Official."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { detected = NetworkSettings.systemProxySummary() }
    }
}
