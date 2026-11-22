import Foundation

/// The shell's user-facing text, in English and Spanish (`Resources/Localizable.xcstrings`).
/// Each comment matches the entry's translator comment in the catalog.
enum AppStrings {
    private static func text(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: key, bundle: .module, comment: comment)
    }

    static let appName = "Afino"

    // MARK: Menu bar icon and app menu

    static var improvePrompt: String { text("menu.improvePrompt", "Menu bar icon's menu: first item, opens the panel") }
    static var settings: String { text("menu.settings", "App menu and menu bar icon's menu: opens Settings") }
    static var checkForUpdates: String { text("menu.checkForUpdates", "Menu bar icon's menu: checks for a new version") }
    static var about: String { text("menu.about", "App menu and menu bar icon's menu: opens About Afino") }
    static var quit: String { text("menu.quit", "App menu and menu bar icon's menu: quits Afino") }
    static var statusItemDescription: String { text("statusItem.accessibility", "VoiceOver label of the menu bar icon, and its tooltip while nothing is happening") }

    // MARK: Main menu (shown only while the welcome is up; it carries the key equivalents)

    static var fileMenu: String { text("menu.file", "Title of the File menu") }
    static var close: String { text("menu.close", "File menu: closes the front window") }
    static var editMenu: String { text("menu.edit", "Title of the Edit menu") }
    static var undo: String { text("menu.undo", "Edit menu: Undo") }
    static var redo: String { text("menu.redo", "Edit menu: Redo") }
    static var cut: String { text("menu.cut", "Edit menu: Cut") }
    static var copy: String { text("menu.copy", "Edit menu: Copy") }
    static var paste: String { text("menu.paste", "Edit menu: Paste") }
    static var selectAll: String { text("menu.selectAll", "Edit menu: Select All") }
    static var windowMenu: String { text("menu.window", "Title of the Window menu") }
    static var minimize: String { text("menu.minimize", "Window menu: Minimize") }

    // MARK: Install location (Release builds)

    static var moveTitle: String { text("install.move.title", "Alert at launch when Afino runs outside Applications: title") }
    static var moveMessage: String { text("install.move.message", "Alert at launch when Afino runs outside Applications: message") }
    static var moveConfirm: String { text("install.move.confirm", "Alert at launch when Afino runs outside Applications: button that moves it there") }
    static var moveLater: String { text("install.move.later", "Alert at launch when Afino runs outside Applications: button that leaves it where it is") }
    static var moveFailedTitle: String { text("install.moveFailed.title", "Title of the alert shown when Afino could not move itself to Applications") }
    static var ok: String { text("alert.ok", "Button of the alert shown when Afino could not move itself to Applications") }
}
