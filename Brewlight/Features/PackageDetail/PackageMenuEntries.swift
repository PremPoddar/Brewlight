import AppKit

extension AppModel {
    /// Everything you can do to a package, as an on-demand menu (detail ⋯ button).
    func menuEntries(for p: Package, openWindow: @escaping @MainActor (String) -> Void) -> [MenuEntry] {
        let id = p.id
        let inst = installed[id]
        var e: [MenuEntry] = []
        if inst == nil {
            e.append(MenuEntry(String(localized: "Install…")) { self.pendingSheet = .install([id]) })
        } else {
            if let out = visibleOutdated[id] {
                e.append(MenuEntry(String(localized: "Upgrade to \(out.available)"), isEnabled: !out.pinned) { self.upgrade([id]) })
                e.append(MenuEntry(String(localized: "Skip Version \(out.available)")) { self.userData.skip(id, version: out.available) })
            }
            if p.kind == .cask, inst?.appPaths.isEmpty == false {
                e.append(MenuEntry(String(localized: "Open")) { self.open(id) })
            }
            e.append(MenuEntry(String(localized: "Reinstall")) { self.reinstall(id) })
            e.append(MenuEntry(String(localized: "Uninstall…")) { self.pendingSheet = .uninstall(id) })
            e.append(MenuEntry(String(localized: "Remove Completely…")) { self.pendingSheet = .removeCompletely(id) })
            if p.kind == .formula {
                let pinned = inst?.isPinned ?? false
                e.append(MenuEntry(pinned ? String(localized: "Unpin") : String(localized: "Pin")) { self.pin(id, !pinned) })
                e.append(MenuEntry(String(localized: "Link")) { self.link(id, true) })
                e.append(MenuEntry(String(localized: "Unlink")) { self.link(id, false) })
            }
            e.append(MenuEntry(String(localized: "Show in Finder")) { self.showInFinder(id) })
        }
        e.append(.separator)
        let fav = userData.favourites.contains(id)
        e.append(MenuEntry(fav ? String(localized: "Remove from Favourites") : String(localized: "Add to Favourites")) {
            self.userData.toggleFavourite(id)
        })
        if !userData.tags.isEmpty {
            e.append(MenuEntry(String(localized: "Tags"), children: userData.tags.map { tag in
                MenuEntry(tag.name, isOn: tag.packageIDs.contains(id)) { self.userData.toggle(tag: tag, on: id) }
            }))
        }
        e.append(.separator)
        e.append(MenuEntry(String(localized: "Open in New Window")) { openWindow(id) })
        if let url = p.homepageURL { e.append(MenuEntry(String(localized: "Open Homepage")) { NSWorkspace.shared.open(url) }) }
        if let src = p.sourceURL { e.append(MenuEntry(String(localized: "View Source")) { NSWorkspace.shared.open(src) }) }
        e.append(MenuEntry(String(localized: "Copy Install Command")) { self.copy(p.installCommand) })
        return e
    }
}
