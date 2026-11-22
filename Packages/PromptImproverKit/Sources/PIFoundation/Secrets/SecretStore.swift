import Foundation

/// Where the user's API keys live. The app's only secrets: never logged, never written to
/// preferences or files, and only ever sent to the provider they belong to.
///
/// A secret is addressed by an account name (`"anthropic"`, `"openai"`). Values are opaque
/// strings to this layer; the type that keeps them from being printed lives with the provider
/// clients.
public protocol SecretStore: Sendable {
    /// The stored secret, or `nil` when there is none. Throws when the store itself fails
    /// (a locked or denied Keychain), which is different from "nothing stored".
    func read(account: String) throws -> String?
    /// Stores `secret`, replacing any earlier one for the account.
    func write(_ secret: String, account: String) throws
    /// Removes the account's secret. Deleting one that does not exist is not an error.
    func delete(account: String) throws
}

/// Why a secret store failed.
public enum SecretStoreError: Error, Equatable, Sendable {
    /// The Keychain refused: `status` is the `OSStatus` it returned.
    case keychain(status: Int32)
    /// The stored bytes were not UTF-8 text.
    case unreadableValue
}

/// For tests, previews and `--in-memory-secrets` runs: nothing leaves memory.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func read(account: String) throws -> String? { lock.withLock { values[account] } }
    public func write(_ secret: String, account: String) throws { lock.withLock { values[account] = secret } }
    public func delete(account: String) throws { lock.withLock { values[account] = nil } }
}

#if DEBUG
/// For contributors who build without the team's signing certificate: reads keys from the
/// environment (set them in the Xcode scheme) and never touches the Keychain, so there is no
/// Keychain prompt on every rebuild. Compiled out of Release builds.
public struct EnvironmentSecretStore: SecretStore {
    private let variables: [String: String]
    private let environment: [String: String]

    /// - Parameter variables: Maps an account to the environment variable that holds its secret.
    public init(variables: [String: String], environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.variables = variables
        self.environment = environment
    }

    public func read(account: String) throws -> String? {
        guard let name = variables[account], let value = environment[name], !value.isEmpty else { return nil }
        return value
    }

    /// Does nothing: the environment is read-only.
    public func write(_ secret: String, account: String) throws {}
    /// Does nothing: the environment is read-only.
    public func delete(account: String) throws {}
}
#endif
