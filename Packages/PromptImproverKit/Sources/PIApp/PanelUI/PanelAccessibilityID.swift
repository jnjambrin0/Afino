/// Stable accessibility identifiers for the panel, for UI tests and Accessibility Inspector.
nonisolated enum PanelAccessibilityID {
    static let panel = "panel"
    static let composeInput = "panel.compose.input"
    static let originRow = "panel.origin"
    static let originToggle = "panel.origin.toggle"
    static let status = "panel.status"
    static let versionStepper = "panel.versions"
    static let result = "panel.result"
    static let errorBlock = "panel.error"
    static let notice = "panel.notice"
    static let footer = "panel.footer"
    static let targetChip = "panel.footer.target"
    static let refineField = "panel.footer.refine"
    static let primaryButton = "panel.footer.primary"
    static let stopButton = "panel.footer.stop"
    static let footerMessage = "panel.footer.message"
    static let actionsMenu = "panel.menu.actions"
    static let targetMenu = "panel.menu.target"
    static let copiedPill = "panel.copied"

    static let setupCard = "panel.setup"
    static let setupKeyField = "panel.setup.key"
    static let setupPaste = "panel.setup.paste"
    static let setupGetKey = "panel.setup.getKey"
    static let setupSave = "panel.setup.save"
    static let setupStatus = "panel.setup.status"

    static let history = "panel.history"
    static let historyFilter = "panel.history.filter"
    static let historyList = "panel.history.list"
    static let historyToast = "panel.history.toast"

    static func hint(_ command: PanelCommand) -> String {
        "panel.footer.hint.\(command)"
    }

    static func historyRow(_ index: Int) -> String {
        "panel.history.row.\(index)"
    }
}
