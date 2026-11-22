import Foundation
import PIFoundation
import PIProviders
import Testing
@testable import PICore

@MainActor
struct CredentialVaultTests {
    private let defaults = EphemeralDefaults()

    private func makeVault(stored: [String: String] = [:], provider: ScriptedProvider = ScriptedProvider()) -> (CredentialVault, InMemorySecretStore) {
        let store = InMemorySecretStore(stored)
        let vault = CredentialVault(store: store, config: ConfigStore(defaults: defaults.defaults), providers: [.anthropic: provider])
        vault.loadStoredKeys()
        return (vault, store)
    }

    @Test
    func aValidKeyIsStoredAndRememberedAsVerified() async throws {
        let provider = ScriptedProvider()
        provider.modelsResult = .success([RemoteModel(id: "claude-sonnet-5-5")])
        let (vault, store) = makeVault(provider: provider)
        var fetched: [RemoteModel] = []
        vault.onModelsFetched = { _, models in fetched = models }
        #expect(vault.state(for: .anthropic) == .missing)

        #expect(await vault.save("  sk-ant-abcdefgh1234  ", for: .anthropic) == .valid)
        #expect(try store.read(account: "anthropic") == "sk-ant-abcdefgh1234")
        #expect(vault.key(for: .anthropic)?.rawValue == "sk-ant-abcdefgh1234")
        #expect(fetched.map(\.id) == ["claude-sonnet-5-5"])
        guard case .valid(let masked) = vault.state(for: .anthropic) else {
            Issue.record("Expected a valid key")
            return
        }
        #expect(!masked.contains("abcdefgh"))

        // A later launch shows it as valid without contacting anyone.
        let relaunched = CredentialVault(store: store, config: ConfigStore(defaults: defaults.defaults), providers: [:])
        relaunched.loadStoredKeys()
        #expect(relaunched.state(for: .anthropic) == .valid(masked: masked))
    }

    @Test
    func aRejectedKeyIsNotStored() async throws {
        let provider = ScriptedProvider()
        provider.modelsResult = .failure(EngineFailure(.invalidKey(.anthropic)))
        let (vault, store) = makeVault(provider: provider)
        #expect(await vault.save("sk-ant-wrong", for: .anthropic) == .rejected)
        #expect(try store.read(account: "anthropic") == nil)
        #expect(vault.state(for: .anthropic) == .missing)
        #expect(!vault.hasAnyUsableKey)
    }

    @Test
    func offlineSavesTheKeyUnverified() async throws {
        let provider = ScriptedProvider()
        provider.modelsResult = .failure(EngineFailure(.offline))
        let (vault, store) = makeVault(provider: provider)
        #expect(await vault.save("sk-ant-offline-key", for: .anthropic) == .savedUnverified)
        #expect(try store.read(account: "anthropic") == "sk-ant-offline-key")
        guard case .unverified = vault.state(for: .anthropic) else {
            Issue.record("Expected an unverified key")
            return
        }
        #expect(vault.state(for: .anthropic).isUsable)
    }

    @Test
    func aKeyForTheOtherProviderIsCaughtBeforeAnyRequest() async {
        let (vault, _) = makeVault()
        #expect(await vault.save("sk-proj-openai-key", for: .anthropic) == .wrongProvider(.openai))
        #expect(await vault.save("sk-ant-key", for: .openai) == .wrongProvider(.anthropic))
        #expect(await vault.save("   ", for: .anthropic) == .empty)
    }

    @Test
    func recheckAndRemove() async throws {
        let provider = ScriptedProvider()
        provider.modelsResult = .failure(EngineFailure(.invalidKey(.anthropic)))
        let (vault, store) = makeVault(stored: ["anthropic": "sk-ant-stored-key"], provider: provider)
        #expect(vault.state(for: .anthropic).isUsable)
        #expect(await vault.recheck(.anthropic) == .rejected)
        guard case .invalid = vault.state(for: .anthropic) else {
            Issue.record("A stored key the provider rejects is shown as invalid")
            return
        }
        // It stays stored until the user replaces or removes it.
        #expect(try store.read(account: "anthropic") == "sk-ant-stored-key")

        vault.remove(.anthropic)
        #expect(try store.read(account: "anthropic") == nil)
        #expect(vault.state(for: .anthropic) == .missing)
        #expect(vault.key(for: .anthropic) == nil)
    }
}
