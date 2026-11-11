import Foundation

/// Installed packages that Homebrew can no longer upgrade cleanly, with why.
/// Detected from installed state vs. the catalog, so the Updates page can offer
/// a proper uninstall instead of letting `brew upgrade` fail on them.
enum CleanupIssues {
    enum Issue: Equatable, Sendable {
        /// Still installed, but no longer in any tap (removed upstream, or its tap is gone).
        case removedFromHomebrew
        /// The app bundle was deleted outside brew (Trash, ⌘⌫) while brew still tracks it.
        case appDeletedOutsideBrew
    }

    static func scan(installed: [InstalledPackage], package: (String) -> Package?)
        -> [(inst: InstalledPackage, issue: Issue)] {
        var result: [(inst: InstalledPackage, issue: Issue)] = []
        for inst in installed {
            if package(inst.id) == nil {
                result.append((inst, .removedFromHomebrew))
            } else if inst.kind == .cask, inst.appPaths.isEmpty,
                      let p = package(inst.id), !p.appNames.isEmpty {
                // Cask expects an .app (per catalog or its receipt) but none exists where brew put it.
                result.append((inst, .appDeletedOutsideBrew))
            }
        }
        return result
    }
}
