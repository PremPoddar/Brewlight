import AppKit
import IOKit.ps
import UserNotifications

/// Periodic `brew update` + outdated check using `NSBackgroundActivityScheduler`, so the system
/// picks an efficient moment. Skips when on battery (by default) or while operations are running.
@MainActor
final class BackgroundChecker {
    private let model: AppModel
    private var scheduler: NSBackgroundActivityScheduler?

    init(model: AppModel) { self.model = model }

    /// Interval from Settings: "1h", "4h", "daily", "manual".
    static var interval: TimeInterval? {
        switch UserDefaults.standard.string(forKey: "checkInterval") ?? "4h" {
        case "1h": 3600
        case "daily": 86_400
        case "manual": nil
        default: 4 * 3600
        }
    }

    func start() {
        scheduler?.invalidate()
        guard let interval = Self.interval else { return }
        let s = NSBackgroundActivityScheduler(identifier: "\(AppInfo.bundleID).update-check")
        s.repeats = true
        s.interval = interval
        s.tolerance = interval / 4
        s.qualityOfService = .utility
        s.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.runCheck()
                completion(.finished)
            }
        }
        scheduler = s
    }

    func runCheck() async {
        guard model.phase == .ready, !model.operations.hasActive else { return }
        let acOnly = UserDefaults.standard.object(forKey: "onlyOnACPower") as? Bool ?? true
        if acOnly && !Self.isOnACPower() { return }
        let before = Set(model.visibleOutdated.keys)
        if let runner = model.runner {
            _ = await runner.output(["update", "--quiet"])
        }
        await model.refreshCatalog()
        await model.refreshOutdated(confirmWithBrew: true)
        let now = model.visibleOutdated.filter { !$0.value.pinned }
        if !Set(now.keys).subtracting(before).isEmpty {
            Notifications.postUpdates(count: now.count, names: now.values.map(\.token).sorted())
        }
        if UserDefaults.standard.bool(forKey: "autoUpgrade") && !now.isEmpty {
            model.upgradeAll()
        }
    }

    static func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPSACPowerValue
    }
}

enum Notifications {
    static let updatesCategory = "UPDATES"
    static let upgradeAllAction = "UPGRADE_ALL"

    static func registerCategories() {
        let upgrade = UNNotificationAction(identifier: upgradeAllAction, title: String(localized: "Upgrade All"), options: [])
        let category = UNNotificationCategory(identifier: updatesCategory, actions: [upgrade], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor static func postUpdates(count: Int, names: [String]) {
        guard UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true,
              !UserDefaults.standard.bool(forKey: "quietMode") else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(count) updates available")
        content.body = names.prefix(5).joined(separator: ", ") + (names.count > 5 ? "…" : "")
        content.categoryIdentifier = updatesCategory
        let request = UNNotificationRequest(identifier: "updates", content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true else { return }
            try? await center.add(request)
        }
    }
}
