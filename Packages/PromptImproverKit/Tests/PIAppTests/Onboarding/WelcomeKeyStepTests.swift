import Foundation
@testable import PIApp
import PICore
import PIFoundation
import PIProviders
import Testing

/// The key step: every outcome of saving a key lands in what the user is told and whether
/// Continue can be pressed, and the provider chosen here is the engine's.
struct WelcomeKeyStepTests {
    private let defaults = EphemeralDefaults()
    private static let key = SettingsSamples.anthropicKey
    private static let masked = "sk-…a1b2"

    private func makeStep(_ vault: FakeVault, clipboard: String? = nil) -> (WelcomeKeyStepModel, SettingsModel) {
        let settings = SettingsModel(store: ConfigStore(defaults: defaults.defaults))
        return (WelcomeKeyStepModel(settings: settings, vault: vault) { clipboard }, settings)
    }

    private var laterLine: String { OnboardingStrings.text("welcome.key.later.note") }
    private func readyLine(_ provider: ProviderID) -> String {
        OnboardingStrings.text("welcome.key.ready", provider.displayName)
    }

    @Test func withoutAKeyTheUserIsToldItCanWait() {
        let (step, _) = makeStep(FakeVault())

        #expect(step.status == .noKey)
        #expect(!step.canContinue)
        #expect(step.offersAddLater)
        #expect(step.statusLine == laterLine)
        #expect(step.entry.displayedMessage == nil)
    }

    @Test func aKeyAlreadyStoredIsReady() {
        let (step, _) = makeStep(FakeVault([.anthropic: .valid(masked: Self.masked)]))

        #expect(step.status == .ready(.anthropic))
        #expect(step.canContinue)
        #expect(!step.offersAddLater)
        #expect(step.statusLine == readyLine(.anthropic))
    }

    @Test func anAcceptedKeyLetsTheUserContinue() async {
        let vault = FakeVault()
        let (step, _) = makeStep(vault)

        step.entry.draft = Self.key
        await step.entry.save()

        #expect(vault.savedKeys == [Self.key])
        #expect(step.status == .ready(.anthropic))
        #expect(step.canContinue)
        #expect(step.statusLine == readyLine(.anthropic))
        #expect(step.entry.displayedMessage == nil)
    }

    @Test(arguments: [
        (KeyCheckOutcome.savedUnverified, KeyEntryModel.Message.savedUnverified),
        (.savedWithLimitedAccess, .savedWithLimitedAccess),
    ])
    func aKeyThatCouldNotBeCheckedStillLetsTheUserContinueWithAWarning(outcome: KeyCheckOutcome, message: KeyEntryModel.Message) async {
        let vault = FakeVault()
        vault.saveOutcome = outcome
        let (step, _) = makeStep(vault)

        step.entry.draft = Self.key
        await step.entry.save()

        #expect(step.status == .ready(.anthropic))
        #expect(step.canContinue)
        #expect(step.entry.displayedMessage == message)
        #expect(step.statusLine == readyLine(.anthropic))
    }

    @Test(arguments: [
        (KeyCheckOutcome.rejected, KeyEntryModel.Message.rejected(.anthropic)),
        (.storeFailed, .storeFailed),
        (.wrongProvider(.openai), .wrongProvider(.openai)),
    ])
    func aKeyThatFailedIsExplainedAndContinueWaits(outcome: KeyCheckOutcome, message: KeyEntryModel.Message) async {
        let vault = FakeVault()
        vault.saveOutcome = outcome
        let (step, _) = makeStep(vault)

        step.entry.draft = Self.key
        await step.entry.save()

        #expect(step.status == .needsAttention)
        #expect(!step.canContinue)
        #expect(step.offersAddLater)
        #expect(step.entry.displayedMessage == message)
        #expect(step.entry.isInvalid)
        #expect(step.statusLine == laterLine)
    }

    @Test func savingNothingAsksForAKeyWithoutBlamingTheUser() async {
        let (step, _) = makeStep(FakeVault())

        await step.entry.save()

        #expect(step.entry.displayedMessage == .empty)
        #expect(step.status == .noKey)
        #expect(!step.canContinue)
    }

    @Test func whileTheKeyIsCheckedNothingCanBePressed() async {
        let vault = FakeVault()
        vault.holdsChecks = true
        let (step, _) = makeStep(vault)
        step.entry.draft = Self.key

        let saving = Task { await step.entry.save() }
        while !vault.isHoldingACheck { await Task.yield() }

        #expect(step.status == .checking)
        #expect(!step.canContinue)
        #expect(!step.offersAddLater)
        #expect(step.statusLine == nil)

        vault.resume()
        await saving.value
        #expect(step.canContinue)
    }

    @Test func whileAStoredKeyIsBeingReplacedReturnBelongsToTheField() {
        let (step, _) = makeStep(FakeVault([.anthropic: .valid(masked: Self.masked)]))

        step.entry.beginReplacing()
        step.entry.draft = "sk-ant-new"

        #expect(step.status == .ready(.anthropic))
        #expect(!step.canContinue)
        #expect(!step.offersAddLater)

        step.entry.cancelReplacing()
        #expect(step.canContinue)
    }

    @Test func choosingAProviderMakesItTheEngines() {
        let (step, settings) = makeStep(FakeVault([.openai: .valid(masked: "sk-…9f3c")]))
        #expect(step.provider == .anthropic)
        #expect(!step.canContinue)

        step.select(.openai)

        #expect(settings.provider == .openai)
        #expect(step.entry.provider == .openai)
        #expect(step.canContinue)
        #expect(step.statusLine == readyLine(.openai))
    }

    @Test func aKeyForTheOtherProviderCanBeUsedThere() async {
        let vault = FakeVault()
        vault.saveOutcome = .wrongProvider(.openai)
        let (step, settings) = makeStep(vault)
        step.entry.draft = SettingsSamples.openAIKey
        await step.entry.save()
        #expect(step.suggestedProvider == .openai)

        vault.saveOutcome = .valid
        await step.useSuggestedProvider()

        #expect(settings.provider == .openai)
        #expect(vault.savedKeys.last == SettingsSamples.openAIKey)
        #expect(step.status == .ready(.openai))
        #expect(step.entry(for: .anthropic).draft.isEmpty)
    }

    @Test func removingAKeyAsksFirst() {
        let vault = FakeVault([.anthropic: .valid(masked: Self.masked)])
        let (step, _) = makeStep(vault)

        step.requestRemoval()
        #expect(step.pendingRemoval == .anthropic)
        #expect(vault.removals.isEmpty)

        step.confirmRemoval()
        #expect(step.pendingRemoval == nil)
        #expect(vault.removals == [.anthropic])
        #expect(step.status == .noKey)
    }

    @Test func aNewShowingForgetsWhatWasHalfTyped() {
        let (step, _) = makeStep(FakeVault())
        step.entry.draft = "sk-ant-half"
        step.requestRemoval()

        step.reset()

        #expect(step.entry.draft.isEmpty)
        #expect(step.pendingRemoval == nil)
    }
}
