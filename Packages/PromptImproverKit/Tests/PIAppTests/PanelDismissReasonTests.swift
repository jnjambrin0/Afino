@testable import PIApp
import Testing

/// Which ways of closing the panel give the keyboard back to the app that had it.
struct PanelDismissReasonTests {
    @Test(arguments: [PanelDismissReason.escape, .toggle, .closeCommand])
    func closingFromTheKeyboardRestoresThePreviousApp(reason: PanelDismissReason) {
        #expect(reason.restoresPreviousApplication)
    }

    /// The user already chose where the keyboard goes; restoring would fight them. Copy & Close
    /// gave it back before its confirmation, so the hide after it does not do it again.
    @Test(arguments: [PanelDismissReason.outsideClick, .localInteraction, .appDeactivated, .copiedAndClosed])
    func clickingOrSwitchingAwayLeavesTheKeyboardWhereTheUserPutIt(reason: PanelDismissReason) {
        #expect(!reason.restoresPreviousApplication)
    }
}
