import Foundation
import Observation
import PICore
import PIProviders

/// What the key field needs from `CredentialVault`; a protocol so `KeyEntryModel` can be tested
/// against a fake.
@MainActor
protocol KeyVaulting: AnyObject {
    func state(for provider: ProviderID) -> KeyState
    func save(_ rawKey: String, for provider: ProviderID) async -> KeyCheckOutcome
    func recheck(_ provider: ProviderID) async -> KeyCheckOutcome
    func remove(_ provider: ProviderID)
}

extension CredentialVault: KeyVaulting {}

/// One provider's API key field (`EKeyField`): what it shows and what its buttons do.
///
/// The stored key itself never reaches the model: it sees the vault's state (masked) and the text
/// being typed or pasted, which is cleared as soon as it is saved.
@Observable
final class KeyEntryModel {
    /// What the field shows.
    enum Phase: Equatable, Sendable {
        /// No key: the placeholder, Paste.
        case empty
        /// A key being typed: secure entry, Paste, Save (and Cancel while replacing a stored key).
        case editing
        /// Being checked with the provider: masked, a spinner, nothing to press.
        case checking
        /// Accepted: masked, a green badge, Paste, Check, Remove.
        case valid
        /// Rejected (or unreadable): masked, a red ring and a message, Paste, Check, Remove.
        case invalid
        /// Stored but not checked: masked, an orange badge, Check, Remove.
        case unverified
    }

    /// The one line under the field.
    enum Message: Equatable, Sendable {
        case rejected(ProviderID)
        case wrongProvider(ProviderID)
        case savedUnverified
        case savedWithLimitedAccess
        case storeFailed
        case unreadable
        case emptyClipboard
        case empty

        enum Tone: Sendable {
            case error
            case warning
            case note
        }

        /// The catalog key of the message.
        var key: String {
            switch self {
            case .rejected: "settings.key.message.rejected"
            case .wrongProvider: "settings.key.message.wrongProvider"
            case .savedUnverified: "settings.key.message.savedUnverified"
            case .savedWithLimitedAccess: "settings.key.message.limitedAccess"
            case .storeFailed: "settings.key.message.storeFailed"
            case .unreadable: "settings.key.message.unreadable"
            case .emptyClipboard: "settings.key.message.emptyClipboard"
            case .empty: "settings.key.message.empty"
            }
        }

        var tone: Tone {
            switch self {
            case .rejected, .wrongProvider, .storeFailed, .unreadable: .error
            case .savedUnverified, .savedWithLimitedAccess: .warning
            case .emptyClipboard, .empty: .note
            }
        }

        var text: String {
            switch self {
            case .rejected(let provider), .wrongProvider(let provider):
                SettingsStrings.text(key, provider.displayName)
            default:
                SettingsStrings.text(key)
            }
        }
    }

    let provider: ProviderID
    /// The key being typed or pasted. Empty whenever nothing is being entered.
    var draft = "" {
        didSet {
            // Typing again takes back a complaint about the previous attempt.
            if draft != oldValue, message?.tone != .warning { message = nil }
        }
    }

    /// Replacing a stored key: the field over it was clicked.
    private(set) var isReplacing = false
    /// A save or a check is waiting for the vault.
    private(set) var isBusy = false
    private(set) var message: Message?

    /// Called after a key was saved, with the provider, so the owner can switch to that provider
    /// when the one in use has no key.
    @ObservationIgnored var onSaved: ((ProviderID) -> Void)?

    @ObservationIgnored private let vault: any KeyVaulting
    @ObservationIgnored private let readClipboard: () -> String?

    /// - Parameter readClipboard: Asked only when Paste is pressed.
    init(provider: ProviderID, vault: any KeyVaulting, readClipboard: @escaping () -> String?) {
        self.provider = provider
        self.vault = vault
        self.readClipboard = readClipboard
    }

    var storedState: KeyState { vault.state(for: provider) }

    var phase: Phase {
        if isBusy { return .checking }
        if case .checking = storedState { return .checking }
        if isReplacing { return .editing }
        switch storedState {
        case .missing: return draft.isEmpty ? .empty : .editing
        case .checking: return .checking
        case .valid: return .valid
        case .unverified: return .unverified
        case .invalid, .unreadable: return .invalid
        }
    }

    /// `sk-…1234` for a stored key; nil while there is none.
    var masked: String? { storedState.masked }

    /// Whether the field draws the red ring.
    var isInvalid: Bool {
        switch phase {
        case .invalid: true
        case .editing: message?.tone == .error
        case .empty, .checking, .valid, .unverified: false
        }
    }

    /// The message under the field: the last outcome, or why a stored key is unusable.
    var displayedMessage: Message? {
        if let message { return message }
        switch storedState {
        case .unreadable: return .unreadable
        case .invalid where !isReplacing: return .rejected(provider)
        default: return nil
        }
    }

    var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy }

    /// Whether Cancel goes back to a stored key.
    var canCancel: Bool { isReplacing }

    /// The field was clicked over a stored key: type a new one.
    func beginReplacing() {
        guard !isBusy, masked != nil || storedState == .unreadable else { return }
        isReplacing = true
        draft = ""
        message = nil
    }

    func cancelReplacing() {
        isReplacing = false
        draft = ""
        message = nil
    }

    /// Paste: reads the clipboard (only now) and saves what it holds at once.
    func paste() async {
        guard !isBusy else { return }
        let text = readClipboard()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            message = .emptyClipboard
            return
        }
        draft = text
        await save()
    }

    func save() async {
        guard !isBusy else { return }
        guard canSave else {
            message = .empty
            return
        }
        isBusy = true
        let outcome = await vault.save(draft, for: provider)
        isBusy = false
        switch outcome {
        case .valid:
            finishSaving(message: nil)
        case .savedUnverified:
            finishSaving(message: .savedUnverified)
        case .savedWithLimitedAccess:
            finishSaving(message: .savedWithLimitedAccess)
        case .rejected:
            message = .rejected(provider)
        case .wrongProvider(let other):
            message = .wrongProvider(other)
        case .empty:
            message = .empty
        case .storeFailed:
            message = .storeFailed
        }
    }

    /// Check: asks the provider about the stored key again.
    func check() async {
        guard !isBusy, masked != nil else { return }
        isBusy = true
        message = nil
        let outcome = await vault.recheck(provider)
        isBusy = false
        switch outcome {
        case .valid, .empty: message = nil
        case .rejected: message = .rejected(provider)
        case .savedUnverified: message = .savedUnverified
        case .savedWithLimitedAccess: message = .savedWithLimitedAccess
        case .storeFailed: message = .storeFailed
        case .wrongProvider(let other): message = .wrongProvider(other)
        }
    }

    /// Remove, once confirmed.
    func remove() {
        vault.remove(provider)
        draft = ""
        isReplacing = false
        message = nil
    }

    private func finishSaving(message: Message?) {
        // `draft`'s observer clears messages; set the outcome after it.
        draft = ""
        isReplacing = false
        self.message = message
        onSaved?(provider)
    }
}
