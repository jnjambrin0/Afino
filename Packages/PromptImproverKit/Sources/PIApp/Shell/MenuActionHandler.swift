import AppKit

/// Runs a closure as the action of a menu item, and says whether the item is enabled.
final class MenuActionHandler: NSObject, NSMenuItemValidation {
    private let action: () -> Void
    private let isEnabled: () -> Bool

    init(_ action: @escaping () -> Void, isEnabled: @escaping () -> Bool = { true }) {
        self.action = action
        self.isEnabled = isEnabled
    }

    @objc func run() {
        action()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isEnabled()
    }

    /// A menu item that runs `action`. An item does not retain its target; its
    /// `representedObject` is what keeps the handler alive with it.
    static func item(
        _ title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        isEnabled: @escaping () -> Bool = { true },
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let handler = MenuActionHandler(action, isEnabled: isEnabled)
        let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.run), keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = handler
        item.representedObject = handler
        return item
    }
}

/// What the app's menus can do. The menu bar item and the main menu share it.
struct AppMenuActions {
    let showPanel: () -> Void
    let showSettings: () -> Void
    let checkForUpdates: () -> Void
    let canCheckForUpdates: () -> Bool
    let showAbout: () -> Void
}
