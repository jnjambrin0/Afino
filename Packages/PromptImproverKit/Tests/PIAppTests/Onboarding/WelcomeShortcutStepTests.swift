import AppKit
import Carbon.HIToolbox
import Foundation
@testable import PIApp
import PICore
import PIDesign
import PIFoundation
import Testing

/// The shortcut step: pressing the activation shortcut while it shows is caught and celebrated
/// instead of opening the panel, and only then; the step says why there is no shortcut when there
/// is none; and the keys are spoken as words.
struct WelcomeShortcutStepTests {
    private let defaults = EphemeralDefaults()

    private func makeFlow() -> WelcomeFlow {
        WelcomeFlow(settings: SettingsModel(store: ConfigStore(defaults: defaults.defaults)))
    }

    private func makeStep(_ config: ConfigStore) -> WelcomeShortcutStepModel {
        let hotKeys = HotKeyCenter()
        let activation = ActivationShortcut(config: config, hotKeys: hotKeys)
        return WelcomeShortcutStepModel(
            activation: activation,
            config: config,
            field: ShortcutFieldModel(activation: activation, recorder: ShortcutRecorder(hotKeys: hotKeys)) { _ in true }
        )
    }

    // MARK: Trying it

    @Test func pressingTheShortcutOnItsStepIsCaughtAndCelebrated() {
        let flow = makeFlow()
        flow.present(at: .shortcut)
        #expect(!flow.hasTriedShortcut)

        #expect(flow.activationShortcutPressed())
        #expect(flow.hasTriedShortcut)
        #expect(flow.shortcutPressCount == 1)
        // Each press is caught (and the caps press again).
        #expect(flow.activationShortcutPressed())
        #expect(flow.shortcutPressCount == 2)
        #expect(flow.step == .shortcut)
        #expect(flow.isPresented)
    }

    @Test(arguments: [WelcomeStep.welcome, .apiKey, .keys])
    func onTheOtherStepsTheShortcutOpensThePanelAsUsual(step: WelcomeStep) {
        let flow = makeFlow()
        flow.present(at: step)

        #expect(!flow.activationShortcutPressed())
        #expect(!flow.hasTriedShortcut)
    }

    @Test func onceTheWelcomeIsGoneTheShortcutIsTheShortcutAgain() {
        let flow = makeFlow()
        #expect(!flow.activationShortcutPressed())

        flow.present(at: .shortcut)
        flow.skip()

        #expect(!flow.activationShortcutPressed())
    }

    @Test func aNewShortcutHasNotBeenTriedYet() {
        let flow = makeFlow()
        flow.present(at: .shortcut)
        _ = flow.activationShortcutPressed()

        flow.shortcutDidChange()

        #expect(!flow.hasTriedShortcut)
        #expect(flow.activationShortcutPressed())
        #expect(flow.hasTriedShortcut)
    }

    @Test func theTryIsRememberedAcrossStepsWithinAShowing() {
        let flow = makeFlow()
        flow.present(at: .shortcut)
        _ = flow.activationShortcutPressed()

        flow.advance()
        flow.back()

        #expect(flow.hasTriedShortcut)
    }

    // MARK: No shortcut

    @Test func withBothDefaultsTakenTheStepSaysSoAndNamesThem() throws {
        let step = makeStep(ConfigStore(defaults: defaults.defaults))

        #expect(step.shortcut == nil)
        #expect(step.caps.isEmpty)
        #expect(step.absence == .defaultsTaken)
        let text = try #require(step.absenceText)
        #expect(text.contains(ActivationShortcutDefaults.primary.keyCaps.joined()))
        #expect(text.contains(ActivationShortcutDefaults.fallback.keyCaps.joined()))
    }

    @Test func aShortcutTurnedOffIsToldApart() {
        let config = ConfigStore(defaults: defaults.defaults)
        config.set(JSONConfigValue(nil), for: .activationShortcut)

        let step = makeStep(config)

        #expect(step.absence == .turnedOff)
        #expect(step.absenceText == OnboardingStrings.text("welcome.shortcut.none.off"))
    }

    @Test func aShortcutMacOSRefusedIsNamed() throws {
        let config = ConfigStore(defaults: defaults.defaults)
        let refused = Shortcut(keyCode: kVK_ANSI_J, modifiers: [.control, .option])
        config.set(JSONConfigValue(refused), for: .activationShortcut)

        // Never started, so nothing is registered: as when macOS turns the registration down.
        let step = makeStep(config)

        #expect(step.absence == .refused(refused))
        #expect(try #require(step.absenceText).contains(refused.keyCaps.joined()))
    }

    // MARK: Words

    @Test func keyCapsAreSpokenAsWords() {
        let control = OnboardingStrings.text("welcome.spoken.control")
        let option = OnboardingStrings.text("welcome.spoken.option")
        let command = OnboardingStrings.text("welcome.spoken.command")
        let returnKey = OnboardingStrings.text("welcome.spoken.return")

        #expect(WelcomeSpokenKeys.words(modifiers: [.control, .option], key: "P") == "\(control) \(option) P")
        #expect(WelcomeSpokenKeys.words(for: KeyChord(.char("k"), .command)) == "\(command) K")
        #expect(WelcomeSpokenKeys.words(for: KeyChord(.returnKey)) == returnKey)
        #expect(WelcomeSpokenKeys.words(for: KeyChord(.escape)) == OnboardingStrings.text("welcome.spoken.escape"))
        #expect(WelcomeSpokenKeys.words(for: KeyChord(.upArrow)) == OnboardingStrings.text("welcome.spoken.up"))
        #expect(WelcomeSpokenKeys.words(for: KeyChord(.tab)) == OnboardingStrings.text("welcome.spoken.tab"))
    }
}
