import Foundation
import os
import Security

/// The login keychain: generic passwords, this Mac only, never synced.
///
/// Why not the data-protection keychain: in a Developer ID app it needs a provisioning profile
/// (the `keychain-access-groups` entitlement is restricted on macOS), which would mean profile
/// management and broken contributor builds for the sake of two API keys.
///
/// What this buys and what it costs. The login keychain ties each item to the code signature of
/// the app that created it. For a Developer ID build that requirement is "this bundle identifier,
/// signed by this team", which every later release satisfies, so updates read the keys without a
/// prompt. An ad-hoc build has no stable identity, so macOS would ask for the login password on
/// every launch after every rebuild — which is why no ad-hoc build may ever run under the release
/// bundle identifier. Another app can still *ask* for the item; the user then sees macOS's
/// Allow/Deny prompt.
public struct KeychainSecretStore: SecretStore {
    /// The Keychain service every item of this store is filed under.
    public let service: String
    private let label: String

    /// - Parameters:
    ///   - service: The Keychain service name. The default is derived from the bundle identifier,
    ///     so a development build (`….dev`) keeps its keys apart from the published app's.
    ///   - label: What Keychain Access shows for the item.
    public init(service: String = AppIdentity.bundleIdentifier + ".apikeys", label: String = "Afino API key") {
        self.service = service
        self.label = label
    }

    public func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw SecretStoreError.unreadableValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            Log.logger(.secrets).error("Keychain read failed status=\(status, privacy: .public)")
            throw SecretStoreError.keychain(status: status)
        }
    }

    /// Updates the item in place when it exists, so its access control list (and with it the
    /// "always allow" the user may have given) survives a changed key.
    public func write(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            Log.logger(.secrets).error("Keychain update failed status=\(status, privacy: .public)")
            throw SecretStoreError.keychain(status: status)
        }
        var add = baseQuery(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = label
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            Log.logger(.secrets).error("Keychain add failed status=\(added, privacy: .public)")
            throw SecretStoreError.keychain(status: added)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.logger(.secrets).error("Keychain delete failed status=\(status, privacy: .public)")
            throw SecretStoreError.keychain(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
