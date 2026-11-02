import AppKit

/// `Brewlight -perftour out.txt` drives the real UI through common interactions and writes how long
/// the main thread was busy for each (state change → SwiftUI update → layout → display).
/// Used to keep every interaction inside a frame or two.
@MainActor
enum PerfTour {
    static func runIfRequested(model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-perftour"), i + 1 < args.count else { return }
        let output = URL(fileURLWithPath: args[i + 1])
        var lines: [String] = []
        @MainActor func log(_ s: String) {
            lines.append(s)
            // Written after every line so a stall still leaves a trace.
            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        }

        Task { @MainActor in
            // Wait for the window and the full catalog.
            let start = Date()
            while model.isCatalogLoading && Date().timeIntervalSince(start) < 30 { try? await Task.sleep(for: .milliseconds(20)) }
            for (name, ms) in PerfLog.shared.order.map({ ($0, PerfLog.shared.latest[$0] ?? 0) }) {
                log(String(format: "  %@: %.1f ms", name, ms))
            }
            try? await Task.sleep(for: .seconds(1))

            @MainActor func measure(_ label: String, _ change: () -> Void) async {
                await settle()
                let t0 = ContinuousClock.now
                change()
                if let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    w.contentView?.layoutSubtreeIfNeeded()
                    w.displayIfNeeded()
                }
                let sync = (ContinuousClock.now - t0).milliseconds
                await settle()
                let total = (ContinuousClock.now - t0).milliseconds
                let list = PerfLog.shared.latest["list"] ?? 0
                PerfLog.shared.record("list", ms: 0)
                log(String(format: "%-34@ sync %6.1f ms   until idle %6.1f ms   (list %5.1f ms)", label as NSString, sync, total, list))
            }

            if ProcessInfo.processInfo.arguments.contains("-perfloop") {
                for _ in 0..<15 {
                    await measure("loop Discover") { model.sidebar = .discover }
                    await measure("loop Installed") { model.sidebar = .installed }
                    await measure("loop Categories") { model.sidebar = .categories }
                }
                try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            let installedIDs = model.installed.keys.sorted().prefix(4)
            model.sidebar = .services
            await measure("baseline: no-op") { }
            await measure("baseline: show HUD") { model.showPerfHUD = true }
            await measure("baseline: hide HUD") { model.showPerfHUD = false }
            await measure("services→taps") { model.sidebar = .taps }
            await measure("taps→services") { model.sidebar = .services }
            for section: SidebarItem in [.discover, .installed, .updates, .allPackages, .categories, .services, .maintenance, .history, .installed, .discover] {
                await measure("section \(section.title)") { model.sidebar = section }
            }
            model.sidebar = .installed
            for id in installedIDs { await measure("select \(id)") { model.selectedPackageID = id } }
            model.sidebar = .allPackages
            var typed = ""
            for ch in "ripgrep" {
                typed.append(ch)
                await measure("type \"\(typed)\"") { model.searchText = typed }
            }
            await measure("clear search") { model.searchText = "" }
            await measure("sort: installs 30d") { model.listSort = .popularity }
            await measure("sort: installs 1y") { model.listSort = .installs365 }
            await measure("sort: trending") { model.listSort = .trending }
            await measure("sort: name") { model.listSort = .name }
            await measure("open palette") { model.showPalette = true }
            await measure("close palette") { model.showPalette = false }
            await measure("toggle activity") { model.showActivity.toggle() }
            await measure("toggle activity") { model.showActivity.toggle() }

            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    /// Returns after the main queue has drained twice, i.e. after the pending render pass.
    private static func settle() async {
        for _ in 0..<2 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { c.resume() }
            }
        }
    }
}
