import Foundation
@testable import PIApp
import PICore
import PIDesign
import PIPrompts
import PIProviders
import Testing

/// Which screen shows, what the footer offers in each state, and what the status says.
struct PanelPresentationTests {
    private static let ret = KeyChord(.returnKey)
    private static let esc = KeyChord(.escape)

    private func footer(_ screen: PanelScreen, configure: (inout PanelFooterInput) -> Void = { _ in }) -> PanelFooterSpec {
        var input = PanelFooterInput(screen: screen)
        configure(&input)
        return PanelPresentation.footer(input)
    }

    private func commands(_ spec: PanelFooterSpec) -> [PanelCommand] {
        spec.hints.map(\.command)
    }

    // MARK: Screen

    @Test func overlaysWinOverThePhaseAndTheKeyCardOnlyReplacesTheComposer() {
        #expect(PanelPresentation.screen(phase: .composing, overlay: .none, needsSetup: false) == .compose)
        #expect(PanelPresentation.screen(phase: .composing, overlay: .none, needsSetup: true) == .setup)
        #expect(PanelPresentation.screen(phase: .result, overlay: .none, needsSetup: true) == .result)
        #expect(PanelPresentation.screen(phase: .running(.thinking), overlay: .none, needsSetup: false) == .running)
        #expect(PanelPresentation.screen(phase: .failed(.emptyOutput), overlay: .none, needsSetup: true) == .failed)
        #expect(PanelPresentation.screen(phase: .stopped, overlay: .none, needsSetup: false) == .stopped)
        #expect(PanelPresentation.screen(phase: .result, overlay: .history, needsSetup: false) == .history)
        #expect(PanelPresentation.screen(phase: .composing, overlay: .history, needsSetup: true) == .history)
    }

    // MARK: Compose

    @Test func anEmptyComposerOffersHistoryAndActionsAndADisabledImprove() {
        let spec = footer(.compose)
        #expect(spec.showsTarget)
        #expect(!spec.isTargetDimmed)
        #expect(spec.targetChord == KeyChord(.tab))
        #expect(commands(spec) == [.toggleHistory, .toggleActions])
        #expect(spec.hints.map(\.label) == [.history, .none])
        #expect(spec.primary == .improve)
        #expect(!spec.isPrimaryEnabled)
        #expect(spec.primaryChord == Self.ret)
        #expect(spec.message == nil)
        #expect(!spec.showsRefineField)
        #expect(!spec.showsStop)
    }

    @Test func withHistoryOffTheEmptyComposerOffersOnlyActions() {
        let spec = footer(.compose) { $0.historyEnabled = false }
        #expect(commands(spec) == [.toggleActions])
    }

    @Test func typingSwapsInTheNewLineHintAndEnablesImprove() {
        let spec = footer(.compose) { $0.draftStatus = .acceptable }
        #expect(commands(spec) == [.insertNewline, .toggleActions])
        #expect(spec.hints.first?.chord == KeyChord(.returnKey, .shift))
        #expect(spec.isPrimaryEnabled)
    }

    @Test func aLongDraftGetsAQuietNoteAndStillGoes() {
        let spec = footer(.compose) { $0.draftStatus = .long }
        #expect(spec.message == .longDraft)
        #expect(spec.isPrimaryEnabled)
    }

    @Test func aDraftOverTheHardLimitCannotBeImproved() {
        let spec = footer(.compose) { $0.draftStatus = .tooLong }
        #expect(spec.message == .tooLong)
        #expect(!spec.isPrimaryEnabled)
        #expect(spec.primary == .improve)
    }

    @Test func fullKeyboardAccessDropsTheTabCap() {
        #expect(footer(.compose) { $0.isFullKeyboardAccessEnabled = true }.targetChord == nil)
        #expect(footer(.compose) { $0.targetCount = 1 }.targetChord == nil)
    }

    // MARK: Running

    @Test func runningOffersOnlyStopAndDimsTheTarget() {
        let spec = footer(.running)
        #expect(spec.showsTarget)
        #expect(spec.isTargetDimmed)
        #expect(!spec.isTargetInteractive)
        #expect(spec.targetChord == nil)
        #expect(spec.primary == nil)
        #expect(spec.showsStop)
        #expect(spec.stopChord == Self.esc)
        #expect(spec.hints.isEmpty)
    }

    // MARK: Result

    @Test func aResultOffersCopyAndClose() {
        let spec = footer(.result)
        #expect(spec.showsRefineField)
        #expect(spec.primary == .copyAndClose)
        #expect(spec.primaryChord == Self.ret)
        #expect(commands(spec) == [.toggleActions])
        #expect(spec.targetChord == nil)
        #expect(spec.isTargetInteractive)
    }

    @Test func returnNamesWhatItWillDoOnAResult() {
        #expect(footer(.result) { $0.hasRefineText = true }.primary == .refine)
        #expect(footer(.result) { $0.rewriteTargetName = "Gemini" }.primary == .rewrite(targetName: "Gemini"))
        // Text in the refine field wins: Return refines.
        let both = footer(.result) {
            $0.hasRefineText = true
            $0.rewriteTargetName = "Gemini"
        }
        #expect(both.primary == .refine)
    }

    // MARK: Failed and stopped

    @Test func aFailureWithoutTextOffersEditAndItsRecovery() {
        let spec = footer(.failed) { $0.recovery = .tryAgain }
        #expect(spec.primary == .recovery(.tryAgain))
        #expect(commands(spec) == [.editOriginal, .toggleActions])
        #expect(spec.hints.first?.label == .edit)
        #expect(!spec.showsRefineField)
    }

    @Test func whenTheRecoveryIsEditTheEditHintIsNotRepeated() {
        let spec = footer(.failed) { $0.recovery = .edit }
        #expect(spec.primary == .recovery(.edit))
        #expect(commands(spec) == [.toggleActions])
    }

    @Test func openSettingsIsARecovery() {
        #expect(footer(.failed) { $0.recovery = .openSettings }.primary == .recovery(.openSettings))
    }

    @Test func partialTextAddsCopy() {
        let spec = footer(.failed) { $0.hasDisplayedText = true }
        #expect(commands(spec) == [.copy, .editOriginal, .toggleActions])
        #expect(spec.hints.first?.chord == KeyChord(.char("c"), .command))
    }

    @Test func aRateLimitsWaitDisablesTryAgain() {
        let spec = footer(.failed) { $0.isRecoveryEnabled = false }
        #expect(spec.primary == .recovery(.tryAgain))
        #expect(!spec.isPrimaryEnabled)
    }

    @Test func aStoppedRunOffersCopyEditActionsAndTryAgain() {
        let spec = footer(.stopped) {
            $0.hasDisplayedText = true
            $0.recovery = .edit
            $0.isRecoveryEnabled = false
        }
        #expect(spec.primary == .recovery(.tryAgain))
        #expect(spec.isPrimaryEnabled)
        #expect(commands(spec) == [.copy, .editOriginal, .toggleActions])
    }

    // MARK: Cards

    @Test(arguments: [PanelScreen.setup, .history])
    func cardsHaveNoTargetChip(screen: PanelScreen) {
        let spec = footer(screen)
        #expect(!spec.showsTarget)
        #expect(spec.primary == nil)
    }

    @Test func theHistoryFooterOffersOpenDeleteAndBack() {
        let hints = PanelPresentation.historyHints
        #expect(hints.map(\.command) == [.historyOpen, .historyDelete, .escape])
        #expect(hints.map(\.chord) == [Self.ret, KeyChord(.delete, .command), Self.esc])
    }

    @Test(arguments: [PanelScreen.compose, .running, .result, .failed, .stopped])
    func everyHintShowsTheChordTheKeyMapAnswersTo(screen: PanelScreen) {
        for draftStatus in [DraftValidation.Status.empty, .acceptable] {
            let spec = footer(screen) {
                $0.draftStatus = draftStatus
                $0.hasDisplayedText = true
            }
            for hint in spec.hints {
                #expect(PanelKeyMap.chord(for: hint.command, in: screen) == hint.chord)
            }
            if spec.primary != nil {
                #expect(spec.primaryChord == PanelKeyMap.chord(for: .primary, in: screen))
            }
        }
    }

    // MARK: Status

    @Test func theStatusSaysThinkingThenCountsAfterFiveSeconds() {
        #expect(PanelPresentation.status(phase: .running(.connecting), hasLiveText: false, elapsed: 1, isCopied: false) == .thinking(seconds: nil))
        #expect(PanelPresentation.status(phase: .running(.thinking), hasLiveText: false, elapsed: 4.9, isCopied: false) == .thinking(seconds: nil))
        #expect(PanelPresentation.status(phase: .running(.thinking), hasLiveText: false, elapsed: 7.4, isCopied: false) == .thinking(seconds: 7))
        #expect(PanelPresentation.status(phase: .running(.thinking), hasLiveText: false, elapsed: nil, isCopied: false) == .thinking(seconds: nil))
    }

    @Test func aRetryNamesItsReasonAndTextMeansWriting() {
        #expect(PanelPresentation.status(phase: .running(.retrying(.overloaded)), hasLiveText: false, elapsed: 9, isCopied: false) == .retrying(.overloaded))
        #expect(PanelPresentation.status(phase: .running(.writing), hasLiveText: true, elapsed: 9, isCopied: false) == .writing)
        // A refinement says "Thinking…" until its own first text, whatever the stage.
        #expect(PanelPresentation.status(phase: .running(.writing), hasLiveText: false, elapsed: 1, isCopied: false) == .thinking(seconds: nil))
    }

    @Test func aResultIsCopiedAndOtherPhasesSayNothing() {
        #expect(PanelPresentation.status(phase: .result, hasLiveText: false, elapsed: nil, isCopied: true) == .copied)
        #expect(PanelPresentation.status(phase: .result, hasLiveText: false, elapsed: nil, isCopied: false) == PanelStatus.none)
        #expect(PanelPresentation.status(phase: .composing, hasLiveText: false, elapsed: nil, isCopied: false) == PanelStatus.none)
        #expect(PanelPresentation.status(phase: .stopped, hasLiveText: true, elapsed: nil, isCopied: false) == PanelStatus.none)
        #expect(PanelPresentation.status(phase: .failed(.truncated), hasLiveText: true, elapsed: nil, isCopied: false) == PanelStatus.none)
    }
}
