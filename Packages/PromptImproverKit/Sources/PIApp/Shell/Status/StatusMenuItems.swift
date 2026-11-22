import PIDesign

/// The commands of the menu bar item's menu.
enum StatusMenuCommand: String, CaseIterable, Sendable {
    case improve
    case stop
    case copyLastResult
    case history
    case settings
    case checkForUpdates
    case about
    case quit
}

/// What decides which rows the menu shows.
struct StatusMenuContext: Equatable, Sendable {
    var isRunning = false
    var hasLastResult = false
    /// History is on and something can show it.
    var canShowHistory = false
    var canCheckForUpdates = false
    /// The global shortcut's caps, shown on "Improve a Prompt…".
    var shortcutCaps: [String] = []
}

/// The rows of the menu, in order and in sections. Pure, so what shows when is testable.
enum StatusMenuItems {
    static let settingsChord = KeyChord(.char(","), .command)
    static let quitChord = KeyChord(.char("q"), .command)

    static func items(for context: StatusMenuContext) -> [EMenuItem] {
        var items = [
            EMenuItem(id: StatusMenuCommand.improve.rawValue, title: AppStrings.improvePrompt, symbol: "text.cursor", caps: context.shortcutCaps, section: 0),
        ]
        if context.isRunning {
            items.append(EMenuItem(id: StatusMenuCommand.stop.rawValue, title: SettingsStrings.text("status.stop"), symbol: "stop.circle", section: 0))
        }
        if context.hasLastResult {
            items.append(EMenuItem(id: StatusMenuCommand.copyLastResult.rawValue, title: SettingsStrings.text("status.copyLastResult"), symbol: "doc.on.doc", section: 1))
        }
        if context.canShowHistory {
            items.append(EMenuItem(id: StatusMenuCommand.history.rawValue, title: SettingsStrings.text("status.history"), symbol: "clock", section: 1))
        }
        items += [
            EMenuItem(id: StatusMenuCommand.settings.rawValue, title: AppStrings.settings, symbol: "gearshape", shortcut: settingsChord, section: 2),
            EMenuItem(
                id: StatusMenuCommand.checkForUpdates.rawValue,
                title: AppStrings.checkForUpdates,
                symbol: "arrow.down.circle",
                isEnabled: context.canCheckForUpdates,
                section: 2
            ),
            EMenuItem(id: StatusMenuCommand.about.rawValue, title: AppStrings.about, symbol: "info.circle", section: 3),
            EMenuItem(id: StatusMenuCommand.quit.rawValue, title: AppStrings.quit, symbol: "power", shortcut: quitChord, section: 3),
        ]
        return items
    }
}
