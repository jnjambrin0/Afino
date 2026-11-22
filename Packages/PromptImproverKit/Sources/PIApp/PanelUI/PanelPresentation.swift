import CoreGraphics
import Foundation
import PICore
import PIDesign
import PIPrompts
import PIProviders

/// A screen the panel shows in place of the session's own, whatever the session is doing.
nonisolated enum PanelOverlay: Hashable, Sendable {
    case none
    case history
}

/// What Return does, as the accent button names it.
nonisolated enum PanelPrimaryAction: Hashable, Sendable {
    case improve
    case refine
    case rewrite(targetName: String)
    case copyAndClose
    case recovery(PanelRecovery)
    case saveKey
}

/// The label of a clickable hint in the footer.
nonisolated enum PanelHintLabel: Hashable, Sendable {
    /// Key caps only ("⌘K").
    case none
    case history
    case newLine
    case copy
    case edit
    case open
    case delete
    case back
}

/// One clickable hint: its caps (from `PanelKeyMap`), its word, and the command a click runs.
nonisolated struct PanelHint: Hashable, Sendable {
    var command: PanelCommand
    var label: PanelHintLabel
    var chord: KeyChord
}

/// A quiet line in the footer about the draft's length.
nonisolated enum PanelFooterMessage: Hashable, Sendable {
    /// Over the soft limit: it still goes, it just takes longer.
    case longDraft
    /// Over the hard limit: Improve is disabled until the draft is trimmed.
    case tooLong
}

/// The footer's three slots for one state: the target chip on the leading edge, the refine field
/// (or a length message) in the middle, the hints and the single accent button on the trailing edge.
nonisolated struct PanelFooterSpec: Hashable, Sendable {
    var showsTarget = true
    var isTargetDimmed = false
    var isTargetInteractive = true
    /// ⇥ on the chip in Compose.
    var targetChord: KeyChord?
    var showsRefineField = false
    var message: PanelFooterMessage?
    var hints: [PanelHint] = []
    var primary: PanelPrimaryAction?
    var isPrimaryEnabled = true
    var primaryChord: KeyChord?
    /// Running: a secondary "Stop Esc" instead of the accent button.
    var showsStop = false
    var stopChord: KeyChord?
}

/// What the footer depends on.
nonisolated struct PanelFooterInput: Hashable, Sendable {
    var screen: PanelScreen
    var draftStatus: DraftValidation.Status = .empty
    var hasRefineText = false
    /// Set when the target changed since the shown version was written.
    var rewriteTargetName: String?
    var historyEnabled = true
    var hasDisplayedText = false
    var recovery: PanelRecovery = .tryAgain
    /// False while a rate limit's wait runs.
    var isRecoveryEnabled = true
    var isFullKeyboardAccessEnabled = false
    var targetCount = 4
}

/// What the origin row says on its trailing edge.
nonisolated enum PanelStatus: Hashable, Sendable {
    case none
    /// Waiting for the first text; the seconds appear once the wait passes the threshold.
    case thinking(seconds: Int?)
    case retrying(RetryReason)
    case writing
    case copied
}

/// What the panel's height depends on.
nonisolated struct PanelHeightInput: Hashable, Sendable {
    var screen: PanelScreen
    /// The compose input's height (32 + 20 × lines, 52 for one line).
    var inputHeight: CGFloat = EmberDesign.Panel.inputMinHeight
    /// The origin row: 40, more while the original is expanded.
    var headerHeight: CGFloat = EmberDesign.Panel.headerHeight
    /// The well's content (text plus its vertical padding).
    var contentHeight: CGFloat = 0
    var showsNotice = false
    /// History rows after filtering.
    var historyRows = 0
    /// `min(720, visible height − top offset − 24)` on the panel's screen.
    var maxHeight: CGFloat = EmberDesign.Panel.maxHeightCap
}

/// The pure rules behind what the panel shows: which screen, what the footer offers, what the
/// status says and how tall the panel is. No views, no session, no clock.
nonisolated enum PanelPresentation {
    // MARK: Screen

    /// An overlay wins over the session's phase; the add-a-key card only ever stands in for the
    /// composer.
    static func screen(phase: SessionState.Phase, overlay: PanelOverlay, needsSetup: Bool) -> PanelScreen {
        switch overlay {
        case .history: return .history
        case .none: break
        }
        switch phase {
        case .composing: return needsSetup ? .setup : .compose
        case .running: return .running
        case .result: return .result
        case .failed: return .failed
        case .stopped: return .stopped
        }
    }

    // MARK: Footer

    /// What the footer offers in a state. Every chord it shows comes from `PanelKeyMap`.
    static func footer(_ input: PanelFooterInput) -> PanelFooterSpec {
        let screen = input.screen
        func hint(_ command: PanelCommand, _ label: PanelHintLabel) -> PanelHint? {
            PanelKeyMap.chord(for: command, in: screen).map { PanelHint(command: command, label: label, chord: $0) }
        }
        var spec = PanelFooterSpec()
        spec.primaryChord = PanelKeyMap.chord(for: .primary, in: screen)

        switch screen {
        case .compose:
            let canCycle = !input.isFullKeyboardAccessEnabled && input.targetCount > 1
            spec.targetChord = canCycle ? PanelKeyMap.chord(for: .nextTarget, in: .compose) : nil
            spec.primary = .improve
            spec.isPrimaryEnabled = input.draftStatus == .acceptable || input.draftStatus == .long
            switch input.draftStatus {
            case .empty:
                spec.hints = [input.historyEnabled ? hint(.toggleHistory, .history) : nil, hint(.toggleActions, .none)].compactMap { $0 }
            case .acceptable:
                spec.hints = [hint(.insertNewline, .newLine), hint(.toggleActions, .none)].compactMap { $0 }
            case .long:
                spec.message = .longDraft
                spec.hints = [hint(.toggleActions, .none)].compactMap { $0 }
            case .tooLong:
                spec.message = .tooLong
                spec.hints = [hint(.toggleActions, .none)].compactMap { $0 }
            }

        case .running:
            spec.isTargetDimmed = true
            spec.isTargetInteractive = false
            spec.primaryChord = nil
            spec.showsStop = true
            spec.stopChord = PanelKeyMap.chord(for: .escape, in: .running)

        case .result:
            spec.showsRefineField = true
            spec.hints = [hint(.toggleActions, .none)].compactMap { $0 }
            if input.hasRefineText {
                spec.primary = .refine
            } else if let name = input.rewriteTargetName {
                spec.primary = .rewrite(targetName: name)
            } else {
                spec.primary = .copyAndClose
            }

        case .failed, .stopped:
            let recovery: PanelRecovery = screen == .stopped ? .tryAgain : input.recovery
            spec.primary = .recovery(recovery)
            spec.isPrimaryEnabled = screen == .stopped || input.isRecoveryEnabled
            var hints: [PanelHint?] = []
            if input.hasDisplayedText { hints.append(hint(.copy, .copy)) }
            if recovery != .edit { hints.append(hint(.editOriginal, .edit)) }
            hints.append(hint(.toggleActions, .none))
            spec.hints = hints.compactMap { $0 }

        case .setup, .history:
            spec.showsTarget = false
            spec.primaryChord = nil
        }
        return spec
    }

    /// The history footer's hints: open, delete, back.
    static var historyHints: [PanelHint] {
        [(PanelCommand.historyOpen, PanelHintLabel.open), (.historyDelete, .delete), (.escape, .back)].compactMap { command, label in
            PanelKeyMap.chord(for: command, in: .history).map { PanelHint(command: command, label: label, chord: $0) }
        }
    }

    // MARK: Status

    /// What the result header says on its trailing edge.
    ///
    /// - Parameters:
    ///   - hasLiveText: Whether the run in flight has written anything yet.
    ///   - elapsed: Seconds since the run started.
    static func status(phase: SessionState.Phase, hasLiveText: Bool, elapsed: TimeInterval?, isCopied: Bool) -> PanelStatus {
        switch phase {
        case .running(let stage):
            if case .retrying(let reason) = stage { return .retrying(reason) }
            if hasLiveText { return .writing }
            let seconds = elapsed.flatMap { $0 >= PanelLayout.elapsedThreshold ? Int($0) : nil }
            return .thinking(seconds: seconds)
        case .result:
            return isCopied ? .copied : .none
        case .composing, .failed, .stopped:
            return .none
        }
    }

    // MARK: Height

    /// The panel's height for a state. Compose is the input plus the footer; the result family is
    /// header + well + (notice) + footer with the well clamped between three lines and what the
    /// screen leaves; the cards have fixed heights; nothing is taller than `maxHeight`.
    static func height(_ input: PanelHeightInput) -> CGFloat {
        let footer = EmberDesign.Panel.footerHeight
        let height: CGFloat
        switch input.screen {
        case .compose:
            height = input.inputHeight + footer
        case .running, .result, .failed, .stopped:
            let notice = input.showsNotice ? EmberDesign.Panel.noticeRowHeight : 0
            height = input.headerHeight + wellHeight(input) + notice + footer
        case .setup:
            height = PanelLayout.setupHeight
        case .history:
            height = PanelLayout.historyFilterHeight + historyListHeight(rows: input.historyRows) + footer
        }
        return min(height.rounded(), input.maxHeight)
    }

    /// `clamp(content, 91, maxHeight − header − footer − notice)`.
    static func wellHeight(_ input: PanelHeightInput) -> CGFloat {
        let notice = input.showsNotice ? EmberDesign.Panel.noticeRowHeight : 0
        let minimum = EmberDesign.Panel.wellMinHeight
        let room = input.maxHeight - input.headerHeight - EmberDesign.Panel.footerHeight - notice
        return min(max(input.contentHeight.rounded(.up), minimum), max(minimum, room))
    }

    /// Up to eight rows, or the empty state's three rows' worth.
    static func historyListHeight(rows: Int) -> CGFloat {
        let visible = rows == 0 ? PanelLayout.historyEmptyRows : min(rows, PanelLayout.historyVisibleRows)
        return CGFloat(visible) * PanelLayout.historyRowHeight + 2 * PanelLayout.historyListPadding
    }
}
