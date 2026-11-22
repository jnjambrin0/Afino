import PIDesign

/// What the panel shows, as far as the keyboard, the footer and the height are concerned.
nonisolated enum PanelScreen: Hashable, Sendable, CaseIterable {
    case compose
    case running
    case result
    case failed
    case stopped
    /// No usable key for the chosen provider: the add-a-key card replaces the composer.
    case setup
    case history
}

/// Everything the panel's keyboard, buttons and menus can ask for.
nonisolated enum PanelCommand: Hashable, Sendable {
    /// Return: Improve, Refine, Rewrite for X, Copy & Close, the recovery of a failure or Save
    /// Key, depending on the screen. The accent button always names it.
    case primary
    /// ⌘Return on a result (and on a partial one): copy and close.
    case copyAndClose
    /// Esc: closes a floating card, leaves the history, stops a run, or closes the panel.
    case escape
    /// ⌘. while a run is in flight.
    case stop
    /// ⌘C: the selection, or the whole text shown.
    case copy
    case regenerate
    case retry
    case editOriginal
    case toggleOriginal
    case newPrompt
    /// ⇧Return or ⌥Return in the compose input.
    case insertNewline
    case nextTarget
    case previousTarget
    /// ⌘1…⌘9, zero-based.
    case selectTarget(Int)
    /// ↑ in an empty (or recalled) compose input.
    case recallOlder
    /// ↓ while a recalled draft is shown.
    case recallNewer
    case scrollUp
    case scrollDown
    /// ⌘↓: back to the latest text.
    case jumpToEnd
    case previousVersion
    case nextVersion
    case toggleActions
    case toggleHistory
    case openSettings
    case menuPrevious
    case menuNext
    case menuExecute
    case historyPrevious
    case historyNext
    case historyOpen
    case historyDelete
    case undoDelete
    /// ⌘V in the add-a-key card: paste and check at once.
    case pasteKey
}

/// What the key map needs to know about the panel right now. Everything is a plain value, so the
/// whole table is testable without a window.
nonisolated struct PanelKeyContext: Equatable, Sendable {
    var screen: PanelScreen
    /// A floating card (⌘K or the target menu) is open: it takes the arrows, Return and Esc.
    var isMenuOpen = false
    /// Compose: the draft can be submitted. Elsewhere: the accent button is enabled.
    var isPrimaryEnabled = true
    var canRecallOlder = false
    var canRecallNewer = false
    var targetCount = 4
    /// With Full Keyboard Access, Tab always moves the focus.
    var isFullKeyboardAccessEnabled = false
    var historyEnabled = true
    /// Text is shown in the well (a result, or what a failed or stopped run wrote).
    var hasDisplayedText = false
    /// Part of the result text is selected.
    var hasResultSelection = false
    /// A text field has selected text: ⌘C is its own.
    var hasFieldSelection = false
    var versionCount = 0
    var shownVersion = 0
    var hasHistorySelection = false
    var historyCount = 0
    var canUndoDelete = false

    init(screen: PanelScreen) {
        self.screen = screen
    }
}

/// The single table from a key chord, in a context, to a panel command. The controller asks it
/// first for every key-down while the panel is up; `nil` means the key does not apply here and
/// goes on to the focused text view untouched.
/// Every shortcut the panel displays (footer hints, menus, Settings › Shortcuts) comes from
/// `chord(for:in:)`, so what is shown cannot drift from what the keys do.
nonisolated enum PanelKeyMap {
    // MARK: Lookup

    /// The command `chord` runs in `context`, or `nil` when the key should reach the text view.
    static func command(for chord: KeyChord, in context: PanelKeyContext) -> PanelCommand? {
        if context.isMenuOpen {
            return menuTable.first { $0.chord == chord }?.command
        }
        guard let command = table(for: context.screen).first(where: { $0.chord == chord })?.command else {
            return nil
        }
        return applies(command, in: context) ? command : nil
    }

    /// The chord that triggers `command` on `screen`, or `nil` when the command has no key there.
    /// The first chord listed wins (↩ rather than ⌘↩ for Improve).
    static func chord(for command: PanelCommand, in screen: PanelScreen) -> KeyChord? {
        table(for: screen).first { $0.command == command }?.chord
    }

    /// The chord of a command inside an open floating card.
    static func menuChord(for command: PanelCommand) -> KeyChord? {
        menuTable.first { $0.command == command }?.chord
    }

    /// Every chord the panel answers to on `screen`, in table order, so tests can check the
    /// whole table.
    static func bindings(in screen: PanelScreen) -> [(chord: KeyChord, command: PanelCommand)] {
        table(for: screen).map { ($0.chord, $0.command) }
    }

    // MARK: Chords

    private static let returnKey = KeyChord(.returnKey)
    private static let commandReturn = KeyChord(.returnKey, .command)
    private static let shiftReturn = KeyChord(.returnKey, .shift)
    private static let optionReturn = KeyChord(.returnKey, .option)
    private static let escape = KeyChord(.escape)
    private static let tab = KeyChord(.tab)
    private static let shiftTab = KeyChord(.tab, .shift)
    private static let up = KeyChord(.upArrow)
    private static let down = KeyChord(.downArrow)
    private static let commandDown = KeyChord(.downArrow, .command)

    private static func commandKey(_ character: String) -> KeyChord {
        KeyChord(.char(character), .command)
    }

    /// ⌘1…⌘9 (the welcome's key guide also reads how many there are).
    static let targetChords: [(chord: KeyChord, command: PanelCommand)] = (0..<9).map {
        (commandKey(String($0 + 1)), .selectTarget($0))
    }

    private typealias Binding = (chord: KeyChord, command: PanelCommand)

    private static let menuTable: [Binding] = [
        (up, .menuPrevious),
        (down, .menuNext),
        (returnKey, .menuExecute),
        (escape, .escape),
        (commandKey("k"), .toggleActions),
    ]

    private static let composeTable: [Binding] = [
        (returnKey, .primary),
        (commandReturn, .primary),
        (shiftReturn, .insertNewline),
        (optionReturn, .insertNewline),
        (escape, .escape),
        (tab, .nextTarget),
        (shiftTab, .previousTarget),
        (up, .recallOlder),
        (down, .recallNewer),
        (commandKey("k"), .toggleActions),
        (commandKey("y"), .toggleHistory),
        (commandKey(","), .openSettings),
    ] + targetChords

    private static let runningTable: [Binding] = [
        (escape, .escape),
        (commandKey("."), .stop),
        (commandKey("c"), .copy),
        (commandKey("o"), .toggleOriginal),
        (up, .scrollUp),
        (down, .scrollDown),
        (commandDown, .jumpToEnd),
        (commandKey("k"), .toggleActions),
    ]

    private static let resultTable: [Binding] = [
        (returnKey, .primary),
        (commandReturn, .copyAndClose),
        (escape, .escape),
        (commandKey("c"), .copy),
        (commandKey("r"), .regenerate),
        (commandKey("e"), .editOriginal),
        (commandKey("o"), .toggleOriginal),
        (commandKey("n"), .newPrompt),
        (commandKey("["), .previousVersion),
        (commandKey("]"), .nextVersion),
        (up, .scrollUp),
        (down, .scrollDown),
        (commandDown, .jumpToEnd),
        (commandKey("k"), .toggleActions),
        (commandKey("y"), .toggleHistory),
        (commandKey(","), .openSettings),
    ] + targetChords

    /// Failed and stopped: ↩ is the recovery, ⌘↩ copies what was written and closes.
    private static let problemTable: [Binding] = [
        (returnKey, .primary),
        (commandReturn, .copyAndClose),
        (escape, .escape),
        (commandKey("c"), .copy),
        (commandKey("r"), .retry),
        (commandKey("e"), .editOriginal),
        (commandKey("o"), .toggleOriginal),
        (commandKey("n"), .newPrompt),
        (up, .scrollUp),
        (down, .scrollDown),
        (commandDown, .jumpToEnd),
        (commandKey("k"), .toggleActions),
        (commandKey("y"), .toggleHistory),
        (commandKey(","), .openSettings),
    ] + targetChords

    private static let setupTable: [Binding] = [
        (returnKey, .primary),
        (commandKey("v"), .pasteKey),
        (escape, .escape),
        (commandKey(","), .openSettings),
    ]

    private static let historyTable: [Binding] = [
        (returnKey, .historyOpen),
        (up, .historyPrevious),
        (down, .historyNext),
        (KeyChord(.delete, .command), .historyDelete),
        (commandKey("z"), .undoDelete),
        (escape, .escape),
        (commandKey("y"), .toggleHistory),
        (commandKey(","), .openSettings),
    ]

    private static func table(for screen: PanelScreen) -> [Binding] {
        switch screen {
        case .compose: composeTable
        case .running: runningTable
        case .result: resultTable
        case .failed, .stopped: problemTable
        case .setup: setupTable
        case .history: historyTable
        }
    }

    // MARK: Whether a command applies

    /// A command that does not apply right now is not consumed: the key reaches the text view
    /// (↑ moves the caret in a draft, ⌘C copies the field's own selection, Tab moves the focus).
    private static func applies(_ command: PanelCommand, in context: PanelKeyContext) -> Bool {
        switch command {
        case .primary:
            return context.isPrimaryEnabled
        case .copyAndClose:
            return context.screen == .result || context.hasDisplayedText
        case .copy:
            if context.hasFieldSelection { return false }
            switch context.screen {
            case .running: return context.hasResultSelection
            case .result: return true
            default: return context.hasDisplayedText || context.hasResultSelection
            }
        case .nextTarget, .previousTarget:
            return !context.isFullKeyboardAccessEnabled && context.targetCount > 1
        case .selectTarget(let index):
            return index < context.targetCount
        case .recallOlder:
            return context.canRecallOlder
        case .recallNewer:
            return context.canRecallNewer
        case .scrollUp, .scrollDown, .jumpToEnd:
            return context.screen == .running || context.screen == .result || context.hasDisplayedText
        case .previousVersion:
            return context.versionCount > 1 && context.shownVersion > 0
        case .nextVersion:
            return context.versionCount > 1 && context.shownVersion < context.versionCount - 1
        case .toggleHistory:
            return context.historyEnabled
        case .historyPrevious, .historyNext:
            return context.historyCount > 0
        case .historyOpen, .historyDelete:
            return context.hasHistorySelection
        case .undoDelete:
            return context.canUndoDelete
        case .escape, .stop, .regenerate, .retry, .editOriginal, .toggleOriginal, .newPrompt,
             .insertNewline, .toggleActions, .openSettings, .menuPrevious, .menuNext, .menuExecute,
             .pasteKey:
            return true
        }
    }
}
