import AppKit

/// Renders the main window to PNG for README screenshots and visual checks, e.g.
/// `Brewlight -demo -snapshot out.png -screen updates -appearance dark -select formula:ffmpeg -palette rip`.
/// Only active in demo mode.
@MainActor
enum SnapshotHook {
    static func runIfRequested(model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard AppInfo.isDemo, let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count else { return }
        let output = URL(fileURLWithPath: args[i + 1])
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        if let a = value("-appearance") { Appearance.apply(a) }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            switch value("-screen") ?? "installed" {
            case "discover": model.sidebar = .discover
            case "updates": model.sidebar = .updates
            case "services": model.sidebar = .services
            case "maintenance": model.sidebar = .maintenance
            case "categories": model.sidebar = .categories
            case "all": model.sidebar = .allPackages
            case "adopt": model.sidebar = .adopt
            default: model.sidebar = .installed
            }
            if let sort = value("-sort").flatMap(AppModel.SortOrder.init(rawValue:)) { model.showAll(model.sidebar, sort: sort) }
            if let id = value("-select") { model.selectedPackageID = id }
            if args.contains("-doctor") { await model.runDoctor() }
            if let text = value("-smart") { await model.smartSearch(text) }
            if args.contains("-about") {
                AppDelegate.openAboutWindow?()
                try? await Task.sleep(for: .seconds(1.5))
                if let about = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("about") == true && $0.isVisible }),
                   let view = about.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: output)
                }
                NSApp.terminate(nil)
                return
            }
            if args.contains("-alerttest") {
                model.pendingNotice = .untrustedTaps(["oven-sh/bun"])
                try? await Task.sleep(for: .seconds(1))
                model.pendingNotice = nil
                try? await Task.sleep(for: .seconds(1))
            }
            if let id = value("-install") {
                model.install([id])
                try? await Task.sleep(for: .seconds(1.5))
                let prompted = model.pendingNotice != nil
                model.pendingNotice = nil // the alert is its own window; capture the log underneath
                try? await Task.sleep(for: .seconds(1))
                try? "prompt shown: \(prompted)".write(to: output.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
            if let q = value("-palette") {
                model.paletteSeed = q
                model.showPalette = true
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
                  let view = window.contentView?.superview else {
                let info = NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") visible=\($0.isVisible) main=\($0.canBecomeMain) frame=\($0.frame)" }
                try? ("NO WINDOW\n" + info.joined(separator: "\n")).write(to: output.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil); return
            }
            window.setContentSize(NSSize(width: 1440, height: 900))
            try? await Task.sleep(for: .milliseconds(500))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: output)
            }
            NSApp.terminate(nil)
        }
    }
}
