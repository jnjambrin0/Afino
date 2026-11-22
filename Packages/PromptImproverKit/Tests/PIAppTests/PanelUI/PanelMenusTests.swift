import CoreGraphics
@testable import PIApp
import PIDesign
import PIPrompts
import PIProviders
import Testing

/// The ⌘K menu offers only what applies, with the key map's shortcuts; the target menu checks the
/// current target; floating cards stay on screen.
struct PanelMenusTests {
    private func ids(_ context: PanelActionsMenuContext) -> [String] {
        PanelMenus.actions(context).filter { !$0.item.isHeader }.map(\.id)
    }

    @Test func aResultOffersCopyRefinePromptEngineAndApp() {
        var context = PanelActionsMenuContext(screen: .result)
        context.hasOrigin = true
        context.usableProviders = [.anthropic]
        let entries = PanelMenus.actions(context)
        #expect(ids(context) == [
            "copy", "copyAndClose", "regenerate",
            "refine.shorter", "refine.detailed", "refine.examples",
            "editOriginal", "toggleOriginal", "newPrompt",
            "engine.anthropic.quality", "engine.anthropic.balanced", "engine.anthropic.fast",
            "history", "customInstructions", "settings",
        ])
        let shortcuts = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.item.shortcut) })
        #expect(shortcuts["copy"] == KeyChord(.char("c"), .command))
        #expect(shortcuts["copyAndClose"] == KeyChord(.returnKey, .command))
        #expect(shortcuts["regenerate"] == KeyChord(.char("r"), .command))
        #expect(shortcuts["editOriginal"] == KeyChord(.char("e"), .command))
        #expect(shortcuts["toggleOriginal"] == KeyChord(.char("o"), .command))
        #expect(shortcuts["newPrompt"] == KeyChord(.char("n"), .command))
        #expect(shortcuts["history"] == KeyChord(.char("y"), .command))
        #expect(shortcuts["settings"] == KeyChord(.char(","), .command))
    }

    @Test func theEngineChoiceChecksTheCurrentPresetForEachProviderWithAKey() {
        var context = PanelActionsMenuContext(screen: .compose)
        context.usableProviders = [.anthropic, .openai]
        context.provider = .openai
        context.preset = .fast
        let entries = PanelMenus.actions(context)
        let checked = entries.filter(\.item.isChecked).map(\.id)
        #expect(checked == ["engine.openai.fast"])
        #expect(entries.contains { $0.item.isHeader && $0.id == "engine.anthropic" })
        #expect(entries.first { $0.id == "engine.anthropic.quality" }?.action == .engine(.anthropic, .quality))
    }

    @Test func aProviderWithoutAKeyIsNotOffered() {
        var context = PanelActionsMenuContext(screen: .compose)
        context.usableProviders = [.anthropic]
        #expect(!ids(context).contains { $0.hasPrefix("engine.openai") })
    }

    @Test func composeHasNoResultOrPromptRows() {
        var context = PanelActionsMenuContext(screen: .compose)
        context.usableProviders = [.anthropic]
        #expect(ids(context) == [
            "engine.anthropic.quality", "engine.anthropic.balanced", "engine.anthropic.fast",
            "history", "customInstructions", "settings",
        ])
        context.historyEnabled = false
        #expect(!ids(context).contains("history"))
    }

    @Test func runningOffersStopAndTheOriginalButNotEditOrHistory() {
        var context = PanelActionsMenuContext(screen: .running)
        context.hasOrigin = true
        let entries = PanelMenus.actions(context)
        #expect(ids(context) == ["stop", "toggleOriginal", "customInstructions", "settings"])
        #expect(entries.first { $0.id == "stop" }?.item.shortcut == KeyChord(.char("."), .command))
        // ⌘, is not a running shortcut, so the row shows none.
        #expect(entries.first { $0.id == "settings" }?.item.shortcut == nil)
    }

    @Test func aFailureOffersTryAgainAndCopyDetails() {
        var context = PanelActionsMenuContext(screen: .failed)
        context.hasOrigin = true
        context.hasFailure = true
        #expect(ids(context) == ["retry", "editOriginal", "toggleOriginal", "newPrompt", "history", "customInstructions", "settings", "copyDetails"])
        context.hasDisplayedText = true
        #expect(ids(context).prefix(3) == ["retry", "copy", "copyAndClose"])
    }

    @Test func showOrHideOriginalFollowsTheState() {
        var context = PanelActionsMenuContext(screen: .result)
        context.hasOrigin = true
        let shown = PanelMenus.actions(context).first { $0.id == "toggleOriginal" }?.item.title
        context.isOriginalExpanded = true
        let hidden = PanelMenus.actions(context).first { $0.id == "toggleOriginal" }?.item.title
        #expect(shown == PanelStrings.showOriginal)
        #expect(hidden == PanelStrings.hideOriginal)
    }

    @Test func refinePresetsSendTheirPhrase() {
        var context = PanelActionsMenuContext(screen: .result)
        context.hasOrigin = true
        let shorter = PanelMenus.actions(context).first { $0.id == "refine.shorter" }
        #expect(shorter?.action == .refinePreset(PanelStrings.refineShorter))
    }

    @Test func theTargetMenuHasATitleShortcutsAndACheck() throws {
        let library = try TargetPackLibrary.bundled()
        let entries = PanelMenus.targets(library: library, currentID: "gpt", screen: .compose)
        #expect(entries.first?.item.isHeader == true)
        #expect(entries.first?.item.title == PanelStrings.targetMenuTitle)
        let rows = entries.dropFirst()
        #expect(rows.map(\.id) == library.packs.map { "target.\($0.id)" })
        #expect(rows.filter(\.item.isChecked).map(\.id) == ["target.gpt"])
        #expect(rows.first?.item.shortcut == KeyChord(.char("1"), .command))
        #expect(rows.last?.item.title == PanelStrings.anyModel)
        #expect(PanelMenus.selectableIDs(entries) == rows.map(\.id))
    }

    // MARK: Card placement (screen coordinates, y up)

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func aCardOpensAboveItsAnchorWhenThereIsRoom() {
        let anchor = CGRect(x: 400, y: 500, width: 120, height: 28)
        let frame = PanelCardPlacement.frame(for: CGSize(width: 220, height: 150), anchor: anchor, visibleFrame: screen, edge: .leading, preferAbove: true)
        #expect(frame.minY == anchor.maxY + EmberDesign.Card.anchorGap)
        #expect(frame.minX == anchor.minX)
    }

    @Test func aCardWithoutRoomAboveOpensBelow() {
        let anchor = CGRect(x: 400, y: 700, width: 30, height: 28)
        let frame = PanelCardPlacement.frame(for: CGSize(width: 264, height: 400), anchor: anchor, visibleFrame: screen, edge: .trailing, preferAbove: true)
        #expect(frame.maxY == anchor.minY - EmberDesign.Card.anchorGap)
        #expect(frame.maxX == anchor.maxX)
    }

    @Test func aCardStaysInsideTheScreen() {
        let anchor = CGRect(x: 1430, y: 10, width: 10, height: 10)
        let frame = PanelCardPlacement.frame(for: CGSize(width: 264, height: 900), anchor: anchor, visibleFrame: screen, edge: .leading, preferAbove: true)
        #expect(frame.maxX <= screen.maxX - EmberDesign.Card.edgeMargin)
        #expect(frame.minY >= screen.minY + EmberDesign.Card.edgeMargin)
    }
}
