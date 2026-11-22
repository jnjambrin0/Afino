import Foundation
import PICore
import PIDesign
import PIPrompts
import PIProviders

/// What a menu row does.
nonisolated enum PanelMenuAction: Hashable, Sendable {
    case command(PanelCommand)
    /// One of the refine presets, sent as the phrase in the interface language.
    case refinePreset(String)
    case engine(ProviderID, EnginePreset)
    /// Opens Settings at the custom instructions.
    case customInstructions
    case copyDetails
    case target(String)
}

/// One row of a floating card and what it does (headers do nothing).
struct PanelMenuEntry: Identifiable {
    var item: EMenuItem
    var action: PanelMenuAction?
    var id: String { item.id }
}

/// What the ⌘K menu depends on.
struct PanelActionsMenuContext {
    var screen: PanelScreen
    var hasOrigin = false
    var isOriginalExpanded = false
    var hasDisplayedText = false
    var historyEnabled = true
    var customInstructionsEnabled = false
    /// Providers that have a key worth sending, in menu order.
    var usableProviders: [ProviderID] = []
    var provider: ProviderID = .anthropic
    var preset: EnginePreset = .default
    /// After a failure: "Copy details" is offered.
    var hasFailure = false
}

/// Builds the rows of the two floating cards. Rows that do not apply are left out, not greyed:
/// the menu only ever offers what can happen now. Every shortcut shown comes from `PanelKeyMap`.
enum PanelMenus {
    /// The presets offered under each provider, with the suffix of their row ids.
    private static let engineChoices: [(EnginePreset, String)] = [
        (.quality, "quality"),
        (.balanced, "balanced"),
        (.fast, "fast"),
    ]

    /// The ⌘K menu: result actions, refine presets, the prompt, the engine and the app, each
    /// group present only when it applies.
    static func actions(_ context: PanelActionsMenuContext) -> [PanelMenuEntry] {
        let screen = context.screen
        var entries: [PanelMenuEntry] = []
        var section = 0

        func add(_ id: String, _ title: String, symbol: String? = nil, command: PanelCommand) {
            entries.append(PanelMenuEntry(
                item: EMenuItem(
                    id: id, title: title, symbol: symbol,
                    shortcut: PanelKeyMap.chord(for: command, in: screen), section: section),
                action: .command(command)))
        }

        func add(_ id: String, _ title: String, symbol: String? = nil, isChecked: Bool = false, action: PanelMenuAction) {
            entries.append(PanelMenuEntry(
                item: EMenuItem(id: id, title: title, symbol: symbol, isChecked: isChecked, section: section),
                action: action))
        }

        func nextSection() {
            if entries.last?.item.section == section { section += 1 }
        }

        // Result
        switch screen {
        case .running:
            add("stop", PanelStrings.stop, symbol: "stop.circle", command: .stop)
        case .result:
            add("copy", PanelStrings.copy, symbol: "doc.on.doc", command: .copy)
            add("copyAndClose", PanelStrings.copyAndClose, symbol: "checkmark.circle", command: .copyAndClose)
            add("regenerate", PanelStrings.regenerate, symbol: "arrow.clockwise", command: .regenerate)
        case .failed, .stopped:
            add("retry", PanelStrings.tryAgain, symbol: "arrow.clockwise", command: .retry)
            if context.hasDisplayedText {
                add("copy", PanelStrings.copy, symbol: "doc.on.doc", command: .copy)
                add("copyAndClose", PanelStrings.copyAndClose, symbol: "checkmark.circle", command: .copyAndClose)
            }
        case .compose, .setup, .history:
            break
        }
        nextSection()

        // Refine
        if screen == .result {
            add("refine.shorter", PanelStrings.refineShorter, symbol: "text.badge.minus", action: .refinePreset(PanelStrings.refineShorter))
            add("refine.detailed", PanelStrings.refineDetailed, symbol: "text.badge.plus", action: .refinePreset(PanelStrings.refineDetailed))
            add("refine.examples", PanelStrings.refineExamples, symbol: "text.badge.star", action: .refinePreset(PanelStrings.refineExamples))
            nextSection()
        }

        // Prompt
        if context.hasOrigin {
            if screen != .running {
                add("editOriginal", PanelStrings.editOriginal, symbol: "pencil", command: .editOriginal)
            }
            add(
                "toggleOriginal",
                context.isOriginalExpanded ? PanelStrings.hideOriginal : PanelStrings.showOriginal,
                symbol: "quote.opening", command: .toggleOriginal)
            if screen != .running {
                add("newPrompt", PanelStrings.newPrompt, symbol: "square.and.pencil", command: .newPrompt)
            }
            nextSection()
        }

        // Engine: one group per provider with a usable key; the way out of a rate limit.
        for provider in context.usableProviders {
            entries.append(PanelMenuEntry(
                item: .header(id: "engine.\(provider.rawValue)", title: PanelStrings.menuEngine(provider.displayName), section: section),
                action: nil))
            for (preset, key) in engineChoices {
                add(
                    "engine.\(provider.rawValue).\(key)", title(of: preset),
                    isChecked: context.provider == provider && context.preset == preset,
                    action: .engine(provider, preset))
            }
            nextSection()
        }

        // App
        if context.historyEnabled, screen != .running {
            add("history", PanelStrings.history, symbol: "clock", command: .toggleHistory)
        }
        // The state on a second line: "Custom Instructions…" / "On". Opens Settings.
        entries.append(PanelMenuEntry(
            item: EMenuItem(
                id: "customInstructions", title: PanelStrings.customInstructions, symbol: "text.quote",
                hint: PanelStrings.customInstructionsState(enabled: context.customInstructionsEnabled), section: section),
            action: .customInstructions))
        add("settings", PanelStrings.settings, symbol: "gearshape", command: .openSettings)
        if context.hasFailure {
            add("copyDetails", PanelStrings.copyDetails, symbol: "info.circle", action: .copyDetails)
        }
        return entries
    }

    /// "Write the prompt for": every target, ⌘1…⌘n, a check on the current one.
    static func targets(library: TargetPackLibrary, currentID: String, screen: PanelScreen) -> [PanelMenuEntry] {
        var entries = [PanelMenuEntry(item: .header(id: "target.title", title: PanelStrings.targetMenuTitle, section: 0), action: nil)]
        for (index, pack) in library.packs.enumerated() {
            entries.append(PanelMenuEntry(
                item: EMenuItem(
                    id: "target.\(pack.id)",
                    title: displayName(of: pack),
                    monogram: HistoryRowFormatter.monogram(for: pack),
                    shortcut: PanelKeyMap.chord(for: .selectTarget(index), in: screen),
                    isChecked: pack.id == currentID),
                action: .target(pack.id)))
        }
        return entries
    }

    /// The selectable rows, for ↑/↓.
    static func selectableIDs(_ entries: [PanelMenuEntry]) -> [String] {
        entries.filter { $0.action != nil && $0.item.isEnabled && !$0.item.isHeader }.map(\.id)
    }

    /// The pack's name as the panel shows it ("Any model" is localized).
    static func displayName(of pack: TargetPack) -> String {
        pack.id == "generic" ? PanelStrings.anyModel : pack.displayName
    }

    /// A preset's menu title; a custom preset shows its model ID.
    static func title(of preset: EnginePreset) -> String {
        switch preset {
        case .quality: PanelStrings.presetQuality
        case .balanced: PanelStrings.presetBalanced
        case .fast: PanelStrings.presetFast
        case .custom(let model, _): model
        }
    }
}
