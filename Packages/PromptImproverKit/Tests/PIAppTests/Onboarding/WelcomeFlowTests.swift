import Foundation
@testable import PIApp
import PICore
import PIFoundation
import Testing

/// The welcome's state machine: the steps in order, Back and Continue, every way out marking
/// onboarding completed exactly once, and only Start going on to the panel.
struct WelcomeFlowTests {
    private let defaults = EphemeralDefaults()

    private func makeFlow() -> (WelcomeFlow, SettingsModel) {
        let settings = SettingsModel(store: ConfigStore(defaults: defaults.defaults))
        return (WelcomeFlow(settings: settings), settings)
    }

    @Test func theStepsComeInOrder() {
        #expect(WelcomeStep.allCases == [.welcome, .apiKey, .shortcut, .keys])
        #expect(WelcomeStep.allCases.map(\.number) == [1, 2, 3, 4])
        #expect(WelcomeStep.welcome.previous == nil)
        #expect(WelcomeStep.keys.next == nil)
        for step in WelcomeStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(step.progress.contains("\(step.number)"))
            #expect(step.announcement.contains(step.title))
        }
    }

    @Test func continueWalksForwardAndBackWalksBack() {
        let (flow, settings) = makeFlow()
        flow.present()
        #expect(flow.step == .welcome)
        #expect(flow.isFirstStep)

        flow.advance()
        #expect(flow.step == .apiKey)
        #expect(flow.direction == .forward)
        flow.advance()
        flow.advance()
        #expect(flow.step == .keys)
        #expect(flow.isLastStep)

        flow.back()
        #expect(flow.step == .shortcut)
        #expect(flow.direction == .backward)
        flow.back()
        flow.back()
        flow.back()
        #expect(flow.step == .welcome)
        #expect(flow.isPresented)
        #expect(!settings.onboardingCompleted)
    }

    @Test func startOnTheLastStepFinishesAndCompletesOnboarding() {
        let (flow, settings) = makeFlow()
        var exits: [WelcomeFlow.Exit] = []
        flow.onExit = { exits.append($0) }
        flow.present(at: .keys)

        flow.advance()

        #expect(exits == [.finished])
        #expect(settings.onboardingCompleted)
        #expect(!flow.isPresented)
    }

    @Test(arguments: WelcomeStep.allCases)
    func skippingFromAnyStepCompletesOnboardingWithoutThePanel(step: WelcomeStep) {
        let (flow, settings) = makeFlow()
        var exits: [WelcomeFlow.Exit] = []
        flow.onExit = { exits.append($0) }
        flow.present(at: step)

        flow.skip()
        // A second Esc, or ⌘W while the window goes, does nothing more.
        flow.skip()
        flow.advance()

        #expect(exits == [.skipped])
        #expect(settings.onboardingCompleted)
    }

    @Test func nothingMovesWhileTheWelcomeIsNotShown() {
        let (flow, settings) = makeFlow()
        var exits = 0
        flow.onExit = { _ in exits += 1 }

        flow.advance()
        flow.skip()

        #expect(flow.step == .welcome)
        #expect(exits == 0)
        #expect(!settings.onboardingCompleted)
    }

    @Test func showingAgainStartsOverFromTheFirstStep() {
        let (flow, settings) = makeFlow()
        flow.present(at: .shortcut)
        #expect(flow.activationShortcutPressed())
        flow.hasPlayedIllustration = true
        flow.skip()

        settings.onboardingCompleted = false
        flow.present()

        #expect(flow.step == .welcome)
        #expect(!flow.hasTriedShortcut)
        #expect(!flow.hasPlayedIllustration)
        #expect(flow.isPresented)
    }

    @Test func everyStepChangeIsReported() {
        let (flow, _) = makeFlow()
        var changes: [String] = []
        flow.onStepChange = { old, new in changes.append("\(old.number)→\(new.number)") }
        flow.present()

        flow.advance()
        flow.advance()
        flow.back()

        #expect(changes == ["1→2", "2→3", "3→2"])
    }

    @Test func theStepButtonWaitsForAKeyAndForARecordingToEnd() {
        #expect(WelcomeStep.welcome.isPrimaryEnabled(keyStepCanContinue: false, isRecordingShortcut: true))
        #expect(WelcomeStep.keys.isPrimaryEnabled(keyStepCanContinue: false, isRecordingShortcut: true))
        #expect(!WelcomeStep.apiKey.isPrimaryEnabled(keyStepCanContinue: false, isRecordingShortcut: false))
        #expect(WelcomeStep.apiKey.isPrimaryEnabled(keyStepCanContinue: true, isRecordingShortcut: false))
        #expect(!WelcomeStep.shortcut.isPrimaryEnabled(keyStepCanContinue: true, isRecordingShortcut: true))
        #expect(WelcomeStep.shortcut.isPrimaryEnabled(keyStepCanContinue: false, isRecordingShortcut: false))
    }
}
