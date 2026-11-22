import Foundation
import Testing
@testable import PIFoundation

/// The real Keychain is not exercised here (it would prompt on a machine without the signing
/// identity); the in-memory and environment stores are, since everything above them is tested
/// through this protocol.
struct SecretStoreTests {
    @Test
    func inMemoryStoreRoundTrips() throws {
        let store = InMemorySecretStore()
        #expect(try store.read(account: "anthropic") == nil)
        try store.write("sk-ant-first", account: "anthropic")
        try store.write("sk-ant-second", account: "anthropic")
        try store.write("sk-openai", account: "openai")
        #expect(try store.read(account: "anthropic") == "sk-ant-second")
        try store.delete(account: "anthropic")
        #expect(try store.read(account: "anthropic") == nil)
        #expect(try store.read(account: "openai") == "sk-openai")
        try store.delete(account: "never-stored")
    }

    @Test
    func environmentStoreReadsOnlyMappedNonEmptyVariables() throws {
        let store = EnvironmentSecretStore(
            variables: ["anthropic": "ANTHROPIC_API_KEY", "openai": "OPENAI_API_KEY"],
            environment: ["ANTHROPIC_API_KEY": "sk-ant-env", "OPENAI_API_KEY": "", "OTHER": "x"]
        )
        #expect(try store.read(account: "anthropic") == "sk-ant-env")
        #expect(try store.read(account: "openai") == nil)
        #expect(try store.read(account: "other") == nil)
        try store.write("ignored", account: "anthropic")
        #expect(try store.read(account: "anthropic") == "sk-ant-env")
    }

    @Test
    func keychainServiceFollowsTheBundleIdentifier() {
        #expect(KeychainSecretStore().service == AppIdentity.bundleIdentifier + ".apikeys")
        #expect(KeychainSecretStore(service: "custom").service == "custom")
    }
}
