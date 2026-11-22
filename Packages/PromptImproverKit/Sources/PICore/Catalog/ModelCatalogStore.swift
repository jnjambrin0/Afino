import Foundation
import Observation
import PIProviders

/// The models each provider offers this user: the curated list, refined by what the provider said
/// the key can use the last time a key was checked. Kept in memory; the curated list is always
/// enough to run, so nothing is lost when the app restarts.
@Observable
public final class ModelCatalogStore {
    /// The picker's entries per provider, curated models first.
    public private(set) var entries: [ProviderID: [CatalogEntry]]

    public init() {
        entries = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, ModelCatalog.curated(for: $0)) })
    }

    /// The entries for one provider.
    public func entries(for provider: ProviderID) -> [CatalogEntry] {
        entries[provider] ?? ModelCatalog.curated(for: provider)
    }

    /// Merges what a provider listed for a key into the curated list.
    public func update(_ provider: ProviderID, remote: [RemoteModel]) {
        entries[provider] = ModelCatalog.merge(remote: remote, provider: provider)
    }
}
