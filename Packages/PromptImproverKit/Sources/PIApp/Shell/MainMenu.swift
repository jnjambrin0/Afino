import AppKit

/// The main menu. Afino is an accessory app, so the menu bar shows these menus only while the
/// welcome window has made it a regular app; they exist all the same because key equivalents such
/// as ⌘Q, ⌘, and ⌘W, and the editing shortcuts in text views (⌘X/C/V/A/Z), only work when a main
/// menu defines them.
enum MainMenu {
    static func make(actions: AppMenuActions) -> NSMenu {
        let mainMenu = NSMenu()

        let app = NSMenu()
        app.addItem(MenuActionHandler.item(AppStrings.about, action: actions.showAbout))
        app.addItem(.separator())
        app.addItem(MenuActionHandler.item(AppStrings.settings, keyEquivalent: ",", action: actions.showSettings))
        app.addItem(.separator())
        app.addItem(withTitle: AppStrings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenuItem(AppStrings.appName, app))

        let file = NSMenu()
        file.addItem(withTitle: AppStrings.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(submenuItem(AppStrings.fileMenu, file))

        let edit = NSMenu()
        edit.addItem(withTitle: AppStrings.undo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: AppStrings.redo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: AppStrings.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: AppStrings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: AppStrings.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: AppStrings.selectAll, action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenuItem(AppStrings.editMenu, edit))

        let window = NSMenu()
        window.addItem(withTitle: AppStrings.minimize, action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(submenuItem(AppStrings.windowMenu, window))
        return mainMenu
    }

    private static func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        return item
    }
}
