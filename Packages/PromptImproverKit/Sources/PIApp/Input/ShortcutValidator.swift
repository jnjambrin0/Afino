import AppKit
import Carbon.HIToolbox

/// What else on the Mac answers to a key combination: macOS's own keyboard shortcuts first, then
/// the key equivalents of Afino's menus.
nonisolated struct ShortcutValidator: Sendable {
    /// A keyboard shortcut of macOS that is turned on, as the system reports it.
    struct SystemShortcut: Equatable, Sendable {
        let keyCode: Int
        /// Carbon's modifier mask, compared as it is.
        let carbonModifiers: Int

        init(keyCode: Int, carbonModifiers: Int) {
            self.keyCode = keyCode
            self.carbonModifiers = carbonModifiers
        }
    }

    /// The key equivalent of a menu item, as the item holds it.
    struct MenuKeyEquivalent: Equatable, Sendable {
        let title: String
        let key: String
        let modifiers: NSEvent.ModifierFlags

        init(title: String, key: String, modifiers: NSEvent.ModifierFlags) {
            self.title = title
            self.key = key
            self.modifiers = modifiers
        }

        /// A menu writes ⇧ into the key itself: "C" stands for ⇧C.
        func matches(key shortcutKey: String, modifiers shortcutModifiers: NSEvent.ModifierFlags) -> Bool {
            var modifiers = modifiers.intersection(Shortcut.significantModifiers)
            let lowercased = key.lowercased()
            if lowercased != key {
                modifiers.insert(.shift)
            }
            return lowercased == shortcutKey.lowercased() && modifiers == shortcutModifiers
        }
    }

    private let systemShortcuts: [SystemShortcut]
    private let menuKeyEquivalents: [MenuKeyEquivalent]

    init(systemShortcuts: [SystemShortcut], menuKeyEquivalents: [MenuKeyEquivalent]) {
        self.systemShortcuts = systemShortcuts
        self.menuKeyEquivalents = menuKeyEquivalents
    }

    /// What already answers to `shortcut`, or nil when nothing does.
    ///
    /// - Parameter key: What the shortcut's key types, written as a menu writes key equivalents;
    ///   nil for a key no menu item can have.
    func conflict(for shortcut: Shortcut, key: String?) -> ShortcutConflict? {
        let carbonModifiers = Int(shortcut.carbonModifiers)
        if systemShortcuts.contains(where: { $0.keyCode == shortcut.keyCode && $0.carbonModifiers == carbonModifiers }) {
            return .usedBySystem
        }
        guard let key else { return nil }
        return menuKeyEquivalents.first { $0.matches(key: key, modifiers: shortcut.modifiers) }
            .map { .usedByMenuItem($0.title) }
    }
}

// MARK: The live system

extension ShortcutValidator {
    /// The keyboard shortcuts turned on in System Settings and the key equivalents of the main
    /// menu, as they are now.
    @MainActor
    static func current() -> ShortcutValidator {
        ShortcutValidator(
            systemShortcuts: enabledSystemShortcuts(),
            menuKeyEquivalents: NSApp.mainMenu.map(keyEquivalents(in:)) ?? []
        )
    }

    /// What `keyCode` types, as a menu item's key equivalent would hold it: Return as a carriage
    /// return, any other key as its character on the keyboard layout in use.
    @MainActor
    static func key(forKeyCode keyCode: Int) -> String? {
        if keyCode == kVK_Return { return "\r" }
        return CGKeyCode(exactly: keyCode).flatMap(KeyCodeResolver.character(for:)).map { String($0).lowercased() }
    }

    /// The symbolic hot keys (`CopySymbolicHotKeys`) that are turned on: the shortcuts listed in
    /// System Settings › Keyboard › Keyboard Shortcuts.
    private static func enabledSystemShortcuts() -> [SystemShortcut] {
        var hotKeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotKeys) == noErr,
              let entries = hotKeys?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled] as? Bool == true,
                  let keyCode = entry[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int
            else { return nil }
            return SystemShortcut(keyCode: keyCode, carbonModifiers: modifiers)
        }
    }

    /// Every key equivalent of `menu` and its submenus, depth first.
    @MainActor
    private static func keyEquivalents(in menu: NSMenu) -> [MenuKeyEquivalent] {
        menu.items.flatMap { item -> [MenuKeyEquivalent] in
            var equivalents = item.keyEquivalent.isEmpty
                ? []
                : [MenuKeyEquivalent(title: item.title, key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)]
            if let submenu = item.submenu {
                equivalents += keyEquivalents(in: submenu)
            }
            return equivalents
        }
    }
}
