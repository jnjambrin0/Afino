@testable import PIApp
import PICore
import PIFoundation
import PIProviders
import Testing

/// The API key field's state machine, against a vault that answers with the outcome each test
/// picks: every outcome lands in a phase and a message.
struct KeyEntryModelTests {
    private static let key = SettingsSamples.anthropicKey
    private static let masked = "sk-…a1b2"

    private func model(_ vault: FakeVault, clipboard: String? = nil) -> KeyEntryModel {
        KeyEntryModel(provider: .anthropic, vault: vault) { clipboard }
    }

    @Test func withoutAKeyTheFieldIsEmptyUntilSomethingIsTyped() {
        let entry = model(FakeVault())
        #expect(entry.phase == .empty)
        #expect(entry.displayedMessage == nil)

        entry.draft = "sk-ant"
        #expect(entry.phase == .editing)
        #expect(entry.canSave)
        #expect(!entry.canCancel)
    }

    @Test func aStoredKeyShowsItsState() {
        #expect(model(FakeVault([.anthropic: .valid(masked: Self.masked)])).phase == .valid)
        #expect(model(FakeVault([.anthropic: .unverified(masked: Self.masked)])).phase == .unverified)
        #expect(model(FakeVault([.anthropic: .checking(masked: Self.masked)])).phase == .checking)

        let invalid = model(FakeVault([.anthropic: .invalid(masked: Self.masked)]))
        #expect(invalid.phase == .invalid)
        #expect(invalid.isInvalid)
        #expect(invalid.displayedMessage == .rejected(.anthropic))

        let unreadable = model(FakeVault([.anthropic: .unreadable]))
        #expect(unreadable.phase == .invalid)
        #expect(unreadable.displayedMessage == .unreadable)
    }

    @Test func aValidKeyIsSavedAndClearedFromTheField() async {
        let vault = FakeVault()
        let entry = model(vault)
        var savedFor: [ProviderID] = []
        entry.onSaved = { savedFor.append($0) }

        entry.draft = Self.key
        await entry.save()

        #expect(vault.savedKeys == [Self.key])
        #expect(entry.phase == .valid)
        #expect(entry.masked == Self.masked)
        #expect(entry.draft.isEmpty)
        #expect(entry.displayedMessage == nil)
        #expect(savedFor == [.anthropic])
    }

    @Test(arguments: [
        (KeyCheckOutcome.savedUnverified, KeyEntryModel.Message.savedUnverified, "settings.key.message.savedUnverified"),
        (.savedWithLimitedAccess, .savedWithLimitedAccess, "settings.key.message.limitedAccess"),
    ])
    func aKeyThatCouldNotBeCheckedIsSavedWithAWarning(
        outcome: KeyCheckOutcome, message: KeyEntryModel.Message, key: String
    ) async {
        let vault = FakeVault()
        vault.saveOutcome = outcome
        let entry = model(vault)

        entry.draft = Self.key
        await entry.save()

        #expect(entry.phase == .unverified)
        #expect(entry.displayedMessage == message)
        #expect(message.key == key)
        #expect(message.tone == .warning)
        #expect(entry.draft.isEmpty)
    }

    @Test(arguments: [
        (KeyCheckOutcome.rejected, KeyEntryModel.Message.rejected(.anthropic), "settings.key.message.rejected"),
        (.wrongProvider(.openai), .wrongProvider(.openai), "settings.key.message.wrongProvider"),
        (.storeFailed, .storeFailed, "settings.key.message.storeFailed"),
        (.empty, .empty, "settings.key.message.empty"),
    ])
    func aKeyThatWasNotSavedStaysInTheFieldWithAMessage(
        outcome: KeyCheckOutcome, message: KeyEntryModel.Message, key: String
    ) async {
        let vault = FakeVault()
        vault.saveOutcome = outcome
        let entry = model(vault)
        var saves = 0
        entry.onSaved = { _ in saves += 1 }

        entry.draft = Self.key
        await entry.save()

        #expect(entry.phase == .editing)
        #expect(entry.draft == Self.key)
        #expect(entry.displayedMessage == message)
        #expect(message.key == key)
        #expect(entry.isInvalid == (message.tone == .error))
        #expect(saves == 0)
    }

    @Test func typingAgainTakesBackTheComplaint() async {
        let vault = FakeVault()
        vault.saveOutcome = .rejected
        let entry = model(vault)
        entry.draft = Self.key
        await entry.save()
        #expect(entry.isInvalid)

        entry.draft = Self.key + "x"
        #expect(entry.displayedMessage == nil)
        #expect(!entry.isInvalid)
    }

    @Test func theFieldShowsTheCheckWhileItRuns() async throws {
        let vault = FakeVault()
        vault.holdsChecks = true
        let entry = model(vault)
        entry.draft = Self.key

        let saving = Task { await entry.save() }
        while !vault.isHoldingACheck { await Task.yield() }
        #expect(entry.phase == .checking)
        #expect(!entry.canSave)

        vault.resume()
        await saving.value
        #expect(entry.phase == .valid)
    }

    @Test func pasteReadsTheClipboardAndSavesAtOnce() async {
        let vault = FakeVault()
        let entry = model(vault, clipboard: "  \(Self.key)\n")

        await entry.paste()

        #expect(vault.savedKeys == [Self.key])
        #expect(entry.phase == .valid)
    }

    @Test func pasteWithNothingOnTheClipboardSaysSo() async {
        let vault = FakeVault()
        let entry = model(vault, clipboard: nil)

        await entry.paste()

        #expect(vault.savedKeys.isEmpty)
        #expect(entry.displayedMessage == .emptyClipboard)
        #expect(entry.displayedMessage?.key == "settings.key.message.emptyClipboard")
    }

    @Test(arguments: [
        (KeyCheckOutcome.valid, KeyEntryModel.Phase.valid, KeyEntryModel.Message?.none),
        (.rejected, .invalid, .rejected(.anthropic)),
        (.savedUnverified, .unverified, .savedUnverified),
        (.savedWithLimitedAccess, .unverified, .savedWithLimitedAccess),
    ])
    func checkAsksAboutTheStoredKeyAgain(outcome: KeyCheckOutcome, phase: KeyEntryModel.Phase, message: KeyEntryModel.Message?) async {
        let vault = FakeVault([.anthropic: .unverified(masked: Self.masked)])
        vault.recheckOutcome = outcome
        let entry = model(vault)

        await entry.check()

        #expect(vault.rechecks == 1)
        #expect(entry.phase == phase)
        #expect(entry.displayedMessage == message)
    }

    @Test func replacingAStoredKeyCanBeCancelled() {
        let entry = model(FakeVault([.anthropic: .valid(masked: Self.masked)]))

        entry.beginReplacing()
        #expect(entry.phase == .editing)
        #expect(entry.canCancel)
        entry.draft = "sk-ant-new"

        entry.cancelReplacing()
        #expect(entry.phase == .valid)
        #expect(entry.draft.isEmpty)
    }

    @Test func aRejectedReplacementKeepsTheStoredKey() async {
        let vault = FakeVault([.anthropic: .valid(masked: Self.masked)])
        vault.saveOutcome = .rejected
        let entry = model(vault)

        entry.beginReplacing()
        entry.draft = "sk-ant-api03-wrong-key-0000"
        await entry.save()

        #expect(entry.phase == .editing)
        #expect(entry.displayedMessage == .rejected(.anthropic))
        #expect(vault.state(for: .anthropic) == .valid(masked: Self.masked))

        entry.cancelReplacing()
        #expect(entry.phase == .valid)
    }

    @Test func removeEmptiesTheField() {
        let vault = FakeVault([.anthropic: .invalid(masked: Self.masked)])
        let entry = model(vault)

        entry.remove()

        #expect(vault.removals == [.anthropic])
        #expect(entry.phase == .empty)
        #expect(entry.displayedMessage == nil)
    }

    @Test func everyMessageHasItsText() {
        let messages: [KeyEntryModel.Message] = [
            .rejected(.anthropic), .wrongProvider(.openai), .savedUnverified, .savedWithLimitedAccess,
            .storeFailed, .unreadable, .emptyClipboard, .empty,
        ]
        for message in messages {
            #expect(message.text != message.key, "\(message.key) is missing from Settings.xcstrings")
        }
        #expect(KeyEntryModel.Message.wrongProvider(.openai).text.contains("OpenAI"))
        #expect(KeyEntryModel.Message.rejected(.anthropic).text.contains("Anthropic"))
    }
}

/// The key field with the real vault: a provider that refuses, an offline check, a key pasted
/// into the wrong provider.
struct KeyEntryWithVaultTests {
    @Test func theRealVaultsOutcomesReachTheField() async {
        let defaults = EphemeralDefaults()
        let config = ConfigStore(defaults: defaults.defaults)
        let provider = StubModelsProvider()
        let vault = CredentialVault(store: InMemorySecretStore(), config: config, providers: [.anthropic: provider])
        vault.loadStoredKeys()
        let entry = KeyEntryModel(provider: .anthropic, vault: vault) { nil }

        entry.draft = SettingsSamples.openAIKey
        await entry.save()
        #expect(entry.displayedMessage == .wrongProvider(.openai))

        provider.failure = EngineFailure(.invalidKey(.anthropic), provider: .anthropic)
        entry.draft = SettingsSamples.anthropicKey
        await entry.save()
        #expect(entry.displayedMessage == .rejected(.anthropic))
        #expect(entry.phase == .editing)
        #expect(vault.state(for: .anthropic) == .missing)

        provider.failure = EngineFailure(.offline, provider: .anthropic)
        await entry.save()
        #expect(entry.phase == .unverified)
        #expect(entry.displayedMessage == .savedUnverified)

        provider.failure = nil
        await entry.check()
        #expect(entry.phase == .valid)
        #expect(entry.displayedMessage == nil)
    }
}

/// Lists models, or fails as told: all a key check needs.
private nonisolated final class StubModelsProvider: PromptEngineProvider, @unchecked Sendable {
    let id = ProviderID.anthropic
    var failure: EngineFailure?

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func models(key: APIKey) async throws -> [RemoteModel] {
        if let failure { throw failure }
        return [RemoteModel(id: "claude-sonnet-5-5")]
    }

    func prewarm() async {}
}
