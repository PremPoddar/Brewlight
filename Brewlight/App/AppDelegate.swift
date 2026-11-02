import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var model: AppModel?
    /// Set by the commands (which have SwiftUI's openWindow) so AppKit code can show the main window.
    static var openMainWindow: (() -> Void)?
    static var openAboutWindow: (() -> Void)?
    private var scheduler: BackgroundChecker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply(UserDefaults.standard.string(forKey: "appearance") ?? "system")
        UNUserNotificationCenter.current().delegate = self
        Notifications.registerCategories()
        if let model = Self.model, !AppInfo.isDemo {
            scheduler = BackgroundChecker(model: model)
            scheduler?.start()
        }
        // Without a menu bar extra the window is the whole app: if state restoration brought back
        // no windows (e.g. the app last quit with its window closed), open the main window anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { Self.openMainWindow?() }
        }
        if let model = Self.model {
            SnapshotHook.runIfRequested(model: model)
            PerfTour.runIfRequested(model: model)
        }
        Perf.measure("launch.didFinish") {}
    }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openMainWindow?() }
        return true
    }

    /// Never quit silently with operations running: wait, or cancel them and quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.operations.hasActive else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Homebrew operations are still running")
        alert.informativeText = String(localized: "\(model.operations.active.count) operation(s) haven't finished. Quitting now may leave a package half-installed.")
        alert.addButton(withTitle: String(localized: "Wait"))
        alert.addButton(withTitle: String(localized: "Cancel Operations and Quit"))
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            model.operations.cancelAll()
            Task {
                while model.operations.hasActive { try? await Task.sleep(for: .milliseconds(200)) }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }

    /// Brewfiles dropped on the Dock icon or opened with Brewlight.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Self.model?.sidebar = .brewfile
        Self.model?.pendingSheet = .brewfileImport(url)
    }

    // MARK: Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == Notifications.upgradeAllAction {
                Self.model?.upgradeAll()
            } else {
                Self.model?.sidebar = .updates
                NSApp.activate()
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum Appearance {
    /// "system" | "light" | "dark"
    @MainActor static func apply(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
