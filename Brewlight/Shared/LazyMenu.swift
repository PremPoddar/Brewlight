import AppKit
import SwiftUI

/// One item of a menu built on demand.
struct MenuEntry {
    var title: String
    var isOn: Bool?
    var isEnabled = true
    var isDestructive = false
    var children: [MenuEntry]?
    var action: (@MainActor () -> Void)?
    var isSeparator = false

    init(_ title: String, isOn: Bool? = nil, isEnabled: Bool = true, isDestructive: Bool = false,
         action: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.action = action
    }

    init(_ title: String, children: [MenuEntry]) {
        self.title = title
        self.children = children
    }

    static let separator: MenuEntry = { var e = MenuEntry(""); e.isSeparator = true; return e }()
}

/// A button that builds its NSMenu only when clicked. SwiftUI's `Menu` builds and bridges every
/// item on each update of the view that owns it, which showed up prominently in profiles.
struct LazyMenuButton<Label: View>: View {
    let entries: @MainActor () -> [MenuEntry]
    @ViewBuilder let label: Label

    var body: some View {
        Button { MenuPresenter.show(entries()) } label: { label }
    }
}

@MainActor
enum MenuPresenter {
    /// Pops the menu up under the mouse, like a pull-down.
    static func show(_ entries: [MenuEntry]) {
        let menu = build(entries)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for e in entries {
            if e.isSeparator { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: e.title, action: nil, keyEquivalent: "")
            item.isEnabled = e.isEnabled
            if e.isDestructive {
                item.attributedTitle = NSAttributedString(string: e.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.systemRed,
                ])
            }
            if let on = e.isOn { item.state = on ? .on : .off }
            if let children = e.children {
                item.submenu = build(children)
            } else if let action = e.action {
                let target = ActionTarget(action)
                item.target = target
                item.action = #selector(ActionTarget.run)
                item.representedObject = target // keeps the target alive with the item
            }
            menu.addItem(item)
        }
        return menu
    }

    private final class ActionTarget: NSObject {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        @MainActor @objc func run() { action() }
    }
}
