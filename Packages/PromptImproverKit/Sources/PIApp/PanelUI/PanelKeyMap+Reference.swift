import PIDesign

extension PanelKeyMap {
    /// The panel's shortcuts as Settings › Shortcuts lists them, in three groups (Write, Result,
    /// Navigate). Every chord is read from the key map itself, so the reference cannot disagree
    /// with what the keys do.
    static func referenceGroups() -> [ShortcutReferenceGroup] {
        func rows(_ items: [(String, PanelCommand, PanelScreen)]) -> [ShortcutReferenceGroup.Row] {
            items.compactMap { label, command, screen in
                chord(for: command, in: screen).map { ShortcutReferenceGroup.Row(label: label, chord: $0) }
            }
        }
        let write = rows([
            (PanelStrings.improve, .primary, .compose),
            (PanelStrings.newLine, .insertNewline, .compose),
            (PanelStrings.nextTarget, .nextTarget, .compose),
            (PanelStrings.previousTarget, .previousTarget, .compose),
            (PanelStrings.chooseTarget, .selectTarget(0), .compose),
            (PanelStrings.previousDraft, .recallOlder, .compose),
        ])
        let result = rows([
            (PanelStrings.resultReturn, .primary, .result),
            (PanelStrings.copyAndClose, .copyAndClose, .result),
            (PanelStrings.copy, .copy, .result),
            (PanelStrings.regenerate, .regenerate, .result),
            (PanelStrings.editOriginal, .editOriginal, .result),
            (PanelStrings.showOriginal, .toggleOriginal, .result),
            (PanelStrings.newPrompt, .newPrompt, .result),
            (PanelStrings.previousVersion, .previousVersion, .result),
            (PanelStrings.nextVersion, .nextVersion, .result),
            (PanelStrings.stopRun, .stop, .running),
        ])
        let navigate = rows([
            (PanelStrings.actions, .toggleActions, .compose),
            (PanelStrings.history, .toggleHistory, .compose),
            (PanelStrings.settings, .openSettings, .compose),
            (PanelStrings.jumpToEnd, .jumpToEnd, .result),
            (PanelStrings.closePanel, .escape, .compose),
        ])
        return [
            ShortcutReferenceGroup(title: PanelStrings.groupWrite, rows: write),
            ShortcutReferenceGroup(title: PanelStrings.groupResult, rows: result),
            ShortcutReferenceGroup(title: PanelStrings.groupNavigate, rows: navigate),
        ]
    }
}
