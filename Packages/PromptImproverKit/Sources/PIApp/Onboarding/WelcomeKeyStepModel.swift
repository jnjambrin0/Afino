import AppKit
import Observation
import PICore
import PIProviders

/// The key step: which provider, its key field (`KeyEntryModel`, the one Settings › Engine uses),
/// what the user is told under it and whether Continue can be pressed.
///
/// Choosing a provider makes it the engine's provider at once, as the panel's add-a-key card
/// does: the key the user adds here is the one the panel will use.
@Observable
final class WelcomeKeyStepModel {
    /// The line under the key field.
    enum Status: Equatable, Sendable {
        /// No usable key: the user can add it later, and the panel will ask for it.
        case noKey
        /// The provider is checking the key.
        case checking
        /// A key that can be used (accepted, or saved but not yet checked).
        case ready(ProviderID)
        /// The field says what went wrong (rejected, wrong provider, Keychain…); the user can
        /// fix it or add it later.
        case needsAttention
    }

    /// The provider whose key is waiting for a Remove confirmation.
    var pendingRemoval: ProviderID?

    @ObservationIgnored private let settings: SettingsModel
    @ObservationIgnored private let entries: [ProviderID: KeyEntryModel]

    /// - Parameter readClipboard: Asked only when Paste is pressed.
    init(
        settings: SettingsModel,
        vault: any KeyVaulting,
        readClipboard: @escaping () -> String? = { NSPasteboard.general.string(forType: .string) }
    ) {
        self.settings = settings
        var entries: [ProviderID: KeyEntryModel] = [:]
        for provider in ProviderID.allCases {
            entries[provider] = KeyEntryModel(provider: provider, vault: vault, readClipboard: readClipboard)
        }
        self.entries = entries
    }

    var provider: ProviderID { settings.provider }

    var providers: [ProviderID] { ProviderID.allCases }

    /// The field of the chosen provider.
    var entry: KeyEntryModel { entry(for: provider) }

    func entry(for provider: ProviderID) -> KeyEntryModel {
        // Every provider has one, made in `init`.
        entries[provider] ?? KeyEntryModel(provider: provider, vault: NoKeys()) { nil }
    }

    /// Makes `provider` the engine's provider. Not while a key is being checked.
    func select(_ provider: ProviderID) {
        guard provider != settings.provider, entry.phase != .checking else { return }
        let previous = settings.provider
        settings.provider = provider
        settings.preset = EngineOptions.preset(settings.preset, afterSwitchingFrom: previous, to: provider)
    }

    var status: Status {
        let entry = entry
        switch entry.phase {
        case .checking:
            return .checking
        case .valid, .unverified:
            return .ready(provider)
        case .invalid:
            return .needsAttention
        case .empty, .editing:
            if entry.displayedMessage?.tone == .error { return .needsAttention }
            // A stored key being replaced keeps working until the new one is saved.
            return entry.isReplacing && entry.storedState.isUsable ? .ready(provider) : .noKey
        }
    }

    /// Continue needs a key that works, and nothing being typed: while the user types, Return
    /// belongs to the field (Save).
    var canContinue: Bool {
        guard case .ready = status else { return false }
        return !entry.isReplacing
    }

    /// What the step says about going on, under the field (the field itself says what went
    /// wrong): that the key is ready, or that it can wait. Nil while a key is being checked.
    var statusLine: String? {
        switch status {
        case .ready(let provider): OnboardingStrings.text("welcome.key.ready", provider.displayName)
        case .noKey, .needsAttention: OnboardingStrings.text("welcome.key.later.note")
        case .checking: nil
        }
    }

    /// "Add it later" is the way on without a key that works.
    var offersAddLater: Bool {
        switch status {
        case .noKey, .needsAttention: true
        case .checking, .ready: false
        }
    }

    /// "This looks like an OpenAI key": the provider to offer instead.
    var suggestedProvider: ProviderID? {
        if case .wrongProvider(let other) = entry.displayedMessage { return other }
        return nil
    }

    /// "Use OpenAI": switches to the provider the key looks like it belongs to and saves it there.
    func useSuggestedProvider() async {
        guard let other = suggestedProvider else { return }
        let draft = entry.draft
        entry.cancelReplacing()
        select(other)
        let target = entry(for: other)
        target.draft = draft
        await target.save()
    }

    /// Remove was pressed in the field: asks first.
    func requestRemoval() {
        pendingRemoval = provider
    }

    func confirmRemoval() {
        guard let provider = pendingRemoval else { return }
        pendingRemoval = nil
        entry(for: provider).remove()
    }

    /// A showing ends: nothing half-typed stays in a field.
    func reset() {
        pendingRemoval = nil
        for entry in entries.values where entry.phase == .editing || entry.isReplacing {
            entry.cancelReplacing()
        }
    }
}

/// The vault of the fallback field that is never shown.
private final class NoKeys: KeyVaulting {
    func state(for provider: ProviderID) -> KeyState { .missing }
    func save(_ rawKey: String, for provider: ProviderID) async -> KeyCheckOutcome { .storeFailed }
    func recheck(_ provider: ProviderID) async -> KeyCheckOutcome { .empty }
    func remove(_ provider: ProviderID) {}
}
