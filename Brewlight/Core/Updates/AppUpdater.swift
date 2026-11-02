import AppKit
import Foundation

/// Brewlight's own updates. One binary, two channels:
/// - **Cask**: the running bundle is the artifact of an installed `brewlight` cask, so updates come
///   from `brew upgrade --cask brewlight` (Homebrew stays the source of truth).
/// - **Direct (DMG)**: Sparkle 2 with an EdDSA-signed appcast. Sparkle is wired in a later
///   milestone; until then "Check for Updates" opens the releases page.
@MainActor @Observable
final class AppUpdater {
    enum Channel: String { case cask, direct }

    private(set) var channel: Channel = .direct
    private(set) var lastResult: String?
    private(set) var isChecking = false

    /// Detects the cask channel by checking whether `<caskroom>/<token>` exists and its
    /// app artifact resolves to this bundle. A plist marker can be faked by a manual copy; this can't.
    func detectChannel(env: BrewEnvironment?) {
        guard let env else { channel = .direct; return }
        let dir = env.caskroom.appending(path: AppInfo.caskToken)
        guard FileManager.default.fileExists(atPath: dir.path) else { channel = .direct; return }
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let receipt = Receipt.read(dir.appending(path: ".metadata/INSTALL_RECEIPT.json"))
        let apps = receipt?.appNames ?? ["\(AppInfo.name).app"]
        channel = apps.contains { bundle.hasSuffix("/" + $0) } ? .cask : .direct
    }

    func check(runner: (any BrewRunning)?, operations: OperationCenter) async {
        isChecking = true
        defer { isChecking = false }
        switch channel {
        case .cask:
            guard let runner else { return }
            let r = await runner.output(["outdated", "--cask", "--greedy", "--json=v2", AppInfo.caskToken])
            let obj = (try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8))) as? [String: Any]
            if let casks = obj?["casks"] as? [[String: Any]], let c = casks.first, let v = c["current_version"] as? String {
                lastResult = String(localized: "Version \(v) is available through Homebrew.")
                operations.enqueue(String(localized: "Upgrade Brewlight"), ["upgrade", "--cask", AppInfo.caskToken], packages: [AppInfo.caskToken])
            } else {
                lastResult = String(localized: "Brewlight is up to date.")
            }
        case .direct:
            NSWorkspace.shared.open(AppInfo.releasesURL)
            lastResult = nil
        }
    }
}
