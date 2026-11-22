@testable import PIApp
import PIDesign
import Testing

/// Which rows the menu bar menu shows, in which order, and with which keys.
struct StatusMenuTests {
    private func ids(_ context: StatusMenuContext) -> [String] {
        StatusMenuItems.items(for: context).map(\.id)
    }

    @Test func atRestTheMenuHasItsFixedRows() {
        #expect(ids(StatusMenuContext()) == ["improve", "settings", "checkForUpdates", "about", "quit"])
    }

    @Test func stopOnlyWhileRunning() {
        #expect(ids(StatusMenuContext(isRunning: true)).contains("stop"))
        #expect(!ids(StatusMenuContext(isRunning: false)).contains("stop"))
    }

    @Test func copyLastResultOnlyWhenThereIsOne() {
        #expect(ids(StatusMenuContext(hasLastResult: true)).contains("copyLastResult"))
        #expect(!ids(StatusMenuContext()).contains("copyLastResult"))
    }

    @Test func historyOnlyWhenItCanBeShown() {
        #expect(ids(StatusMenuContext(canShowHistory: true)).contains("history"))
        #expect(!ids(StatusMenuContext(canShowHistory: false)).contains("history"))
    }

    @Test func everythingInOrder() {
        let all = StatusMenuContext(isRunning: true, hasLastResult: true, canShowHistory: true, canCheckForUpdates: true)
        #expect(ids(all) == StatusMenuCommand.allCases.map(\.rawValue))
    }

    @Test func checkForUpdatesFollowsTheUpdater() {
        let disabled = StatusMenuItems.items(for: StatusMenuContext(canCheckForUpdates: false)).first { $0.id == "checkForUpdates" }
        let enabled = StatusMenuItems.items(for: StatusMenuContext(canCheckForUpdates: true)).first { $0.id == "checkForUpdates" }
        #expect(disabled?.isEnabled == false)
        #expect(enabled?.isEnabled == true)
    }

    @Test func improveShowsTheGlobalShortcutAndTheOthersTheirKeys() {
        let items = StatusMenuItems.items(for: StatusMenuContext(shortcutCaps: ["⌃", "⌥", "P"]))
        #expect(items.first { $0.id == "improve" }?.caps == ["⌃", "⌥", "P"])
        #expect(items.first { $0.id == "settings" }?.shortcut == KeyChord(.char(","), .command))
        #expect(items.first { $0.id == "quit" }?.shortcut == KeyChord(.char("q"), .command))
    }
}
