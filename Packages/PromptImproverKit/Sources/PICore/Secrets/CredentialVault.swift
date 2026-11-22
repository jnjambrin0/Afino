import Foundation
import Observation
import os
import PIFoundation
import PIProviders

/// What the interface may know about a stored key. The key itself never leaves the vault except
/// on its way to its provider.
public nonisolated enum KeyState: Sendable, Equatable {
    /// No key is stored.
    case missing
    /// Being checked with the provider right now.
    case checking(masked: String)
    /// The provider accepted it.
    case valid(masked: String)
    /// Stored, but the check could not run (offline) or the provider did not let it list models.
    case unverified(masked: String)
    /// The provider rejected it. A rejected key that was typed in is not stored; one that was
    /// stored and later stopped working stays until the user replaces or removes it.
    case invalid(masked: String)
    /// The Keychain itself could not be read.
    case unreadable

    /// Whether there is a key worth sending a request with.
    public var isUsable: Bool {
        switch self {
        case .valid, .unverified, .checking: true
        case .missing, .invalid, .unreadable: false
        }
    }

    /// The key as the interface may show it (`sk-…wxyz`), when there is one.
    public var masked: String? {
        switch self {
        case .checking(let masked), .valid(let masked), .unverified(let masked), .invalid(let masked): masked
        case .missing, .unreadable: nil
        }
    }
}

/// What came of saving or re-checking a key.
public nonisolated enum KeyCheckOutcome: Sendable, Equatable {
    /// The provider accepted it.
    case valid
    /// Saved; the provider could not be reached to check it.
    case savedUnverified
    /// Saved; the key works for requests but may not list models.
    case savedWithLimitedAccess
    /// The provider rejected it. A typed key is not saved.
    case rejected
    /// The key looks like it belongs to the other provider; nothing was sent or saved.
    case wrongProvider(ProviderID)
    /// There was no key to check.
    case empty
    /// The provider accepted it but the Keychain could not store it.
    case storeFailed
}

/// The user's API keys: reads and writes the secret store, checks keys with their provider and
/// publishes what the interface may show.
@Observable
public final class CredentialVault {
    /// What the interface may show per provider; a provider without an entry has no key.
    public private(set) var states: [ProviderID: KeyState] = [:]

    @ObservationIgnored private let store: any SecretStore
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let providers: [ProviderID: any PromptEngineProvider]
    @ObservationIgnored private var cache: [ProviderID: APIKey] = [:]
    /// Called with the models a key can use whenever a check succeeds, so the catalog is fresh.
    @ObservationIgnored public var onModelsFetched: ((ProviderID, [RemoteModel]) -> Void)?

    public init(store: any SecretStore, config: ConfigStore, providers: [ProviderID: any PromptEngineProvider]) {
        self.store = store
        self.config = config
        self.providers = providers
    }

    /// The provider's key state, `.missing` when nothing is known.
    public func state(for provider: ProviderID) -> KeyState {
        states[provider] ?? .missing
    }

    /// Whether any provider has a key that can be used.
    public var hasAnyUsableKey: Bool {
        ProviderID.allCases.contains { state(for: $0).isUsable }
    }

    /// Reads what is stored, without contacting anyone. Call once at launch.
    public func loadStoredKeys() {
        for provider in ProviderID.allCases {
            do {
                guard let raw = try store.read(account: provider.rawValue), !APIKey(raw).isEmpty else {
                    cache[provider] = nil
                    states[provider] = .missing
                    continue
                }
                let key = APIKey(raw)
                cache[provider] = key
                states[provider] = config.value(for: Self.verifiedKey(provider)) ? .valid(masked: key.masked) : .unverified(masked: key.masked)
            } catch {
                cache[provider] = nil
                states[provider] = .unreadable
            }
        }
    }

    /// The key to send with a request, or `nil` when there is none.
    public func key(for provider: ProviderID) -> APIKey? {
        cache[provider]
    }

    /// Checks a typed or pasted key with its provider and stores it unless it was rejected.
    @discardableResult
    public func save(_ rawKey: String, for provider: ProviderID) async -> KeyCheckOutcome {
        let key = APIKey(rawKey)
        guard !key.isEmpty else { return .empty }
        if let other = Self.likelyProvider(of: key), other != provider { return .wrongProvider(other) }

        let previous = states[provider]
        states[provider] = .checking(masked: key.masked)
        let check = await check(key, provider: provider)
        guard check != .rejected else {
            states[provider] = previous ?? .missing
            return .rejected
        }
        do {
            try store.write(key.rawValue, account: provider.rawValue)
        } catch {
            states[provider] = previous ?? .missing
            return .storeFailed
        }
        cache[provider] = key
        apply(check, key: key, provider: provider)
        return check
    }

    /// Checks the stored key again (the "Check" button, or after a request was refused).
    @discardableResult
    public func recheck(_ provider: ProviderID) async -> KeyCheckOutcome {
        guard let key = cache[provider] else { return .empty }
        states[provider] = .checking(masked: key.masked)
        let check = await check(key, provider: provider)
        apply(check, key: key, provider: provider)
        return check
    }

    /// Marks the stored key as rejected after the provider refused a real request with it.
    public func markRejected(_ provider: ProviderID) {
        guard let key = cache[provider] else { return }
        config.set(false, for: Self.verifiedKey(provider))
        states[provider] = .invalid(masked: key.masked)
    }

    /// Deletes the provider's key and forgets that it was verified.
    public func remove(_ provider: ProviderID) {
        try? store.delete(account: provider.rawValue)
        cache[provider] = nil
        config.reset(Self.verifiedKey(provider))
        states[provider] = .missing
    }

    private func apply(_ outcome: KeyCheckOutcome, key: APIKey, provider: ProviderID) {
        switch outcome {
        case .valid:
            config.set(true, for: Self.verifiedKey(provider))
            states[provider] = .valid(masked: key.masked)
        case .rejected:
            config.set(false, for: Self.verifiedKey(provider))
            states[provider] = .invalid(masked: key.masked)
        default:
            config.set(false, for: Self.verifiedKey(provider))
            states[provider] = .unverified(masked: key.masked)
        }
    }

    /// Lists the provider's models with the key: proves the key is accepted without spending a
    /// token. It does not prove the account has credit.
    private func check(_ key: APIKey, provider: ProviderID) async -> KeyCheckOutcome {
        guard let client = providers[provider] else { return .savedUnverified }
        do {
            let models = try await client.models(key: key)
            onModelsFetched?(provider, models)
            return .valid
        } catch {
            switch EngineFailure(normalizing: error, provider: provider).error {
            case .invalidKey: return .rejected
            case .permissionDenied: return .savedWithLimitedAccess
            default: return .savedUnverified
            }
        }
    }

    private static func verifiedKey(_ provider: ProviderID) -> ConfigKey<Bool> {
        ConfigKey("keyVerified.\(provider.rawValue)", default: false)
    }

    /// A hint from the key's prefix; only used to catch a key pasted into the wrong provider.
    nonisolated static func likelyProvider(of key: APIKey) -> ProviderID? {
        let raw = key.rawValue
        if raw.hasPrefix("sk-ant-") { return .anthropic }
        if raw.hasPrefix("sk-") { return .openai }
        return nil
    }
}
