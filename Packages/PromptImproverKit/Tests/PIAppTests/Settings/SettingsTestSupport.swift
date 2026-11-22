import AppKit
@testable import PIApp
import PICore
import PIDesign
import PIFoundation
import PIProviders

/// A vault that answers as `CredentialVault` does, with the outcome each test chooses.
final class FakeVault: KeyVaulting {
    var states: [ProviderID: KeyState] = [:]
    var saveOutcome: KeyCheckOutcome = .valid
    var recheckOutcome: KeyCheckOutcome = .valid
    /// While set, `save` and `recheck` wait for the test to call `resume()`.
    var holdsChecks = false
    private(set) var savedKeys: [String] = []
    private(set) var rechecks = 0
    private(set) var removals: [ProviderID] = []
    private var pending: CheckedContinuation<Void, Never>?

    init(_ states: [ProviderID: KeyState] = [:]) {
        self.states = states
    }

    func state(for provider: ProviderID) -> KeyState {
        states[provider] ?? .missing
    }

    func save(_ rawKey: String, for provider: ProviderID) async -> KeyCheckOutcome {
        savedKeys.append(rawKey)
        let key = APIKey(rawKey)
        let previous = states[provider]
        states[provider] = .checking(masked: key.masked)
        await waitIfHeld()
        switch saveOutcome {
        case .valid: states[provider] = .valid(masked: key.masked)
        case .savedUnverified, .savedWithLimitedAccess: states[provider] = .unverified(masked: key.masked)
        case .rejected, .wrongProvider, .empty, .storeFailed: states[provider] = previous
        }
        return saveOutcome
    }

    func recheck(_ provider: ProviderID) async -> KeyCheckOutcome {
        rechecks += 1
        guard let masked = state(for: provider).masked else { return .empty }
        states[provider] = .checking(masked: masked)
        await waitIfHeld()
        switch recheckOutcome {
        case .valid: states[provider] = .valid(masked: masked)
        case .rejected: states[provider] = .invalid(masked: masked)
        default: states[provider] = .unverified(masked: masked)
        }
        return recheckOutcome
    }

    func remove(_ provider: ProviderID) {
        removals.append(provider)
        states[provider] = .missing
    }

    func resume() {
        pending?.resume()
        pending = nil
    }

    var isHoldingACheck: Bool { pending != nil }

    private func waitIfHeld() async {
        guard holdsChecks else { return }
        await withCheckedContinuation { pending = $0 }
    }
}

/// A login item that turns on and off at once, never waiting for the user's approval.
final class FakeSettingsLoginItems: LoginItemServicing {
    var status: LoginItemStatus

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func setEnabled(_ isEnabled: Bool) throws {
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}

/// Never brings the test process forward.
final class FakeActivator: AppActivating {
    func activate() {}
}

/// Sample keys, targets and shortcuts the Settings tests share.
enum SettingsSamples {
    static let anthropicKey = "sk-ant-api03-example-key-a1b2"
    static let openAIKey = "sk-proj-example-openai-key-9f3c"

    /// The targets the app ships, in picker order.
    static let targets = [
        TargetSummary(id: "claude", name: "Claude", monogram: .letters("Cl")),
        TargetSummary(id: "gpt", name: "GPT", monogram: .letters("Gp")),
        TargetSummary(id: "gemini", name: "Gemini", monogram: .letters("Ge")),
        TargetSummary(id: "generic", name: "Any model", monogram: .symbol("circle.dotted")),
    ]

    /// A fixed sample in the shape of the panel's reference (`PanelKeyMap.referenceGroups()`), so
    /// the Shortcuts pane renders the same whatever the panel's key map holds.
    static let shortcutReference = [
        ShortcutReferenceGroup(title: "Compose", rows: [
            .init(label: "Improve", chord: KeyChord(.returnKey)),
            .init(label: "New line", chord: KeyChord(.returnKey, .shift)),
            .init(label: "Next target", chord: KeyChord(.tab)),
            .init(label: "Choose a target", chord: KeyChord(.char("1"), .command)),
        ]),
        ShortcutReferenceGroup(title: "Result", rows: [
            .init(label: "Copy and close", chord: KeyChord(.returnKey, .command)),
            .init(label: "Regenerate", chord: KeyChord(.char("r"), .command)),
            .init(label: "Edit original", chord: KeyChord(.char("e"), .command)),
            .init(label: "Previous version", chord: KeyChord(.char("["), .command)),
        ]),
        ShortcutReferenceGroup(title: "Anywhere in the panel", rows: [
            .init(label: "Actions", chord: KeyChord(.char("k"), .command)),
            .init(label: "History", chord: KeyChord(.char("y"), .command)),
            .init(label: "Settings", chord: KeyChord(.char(","), .command)),
            .init(label: "Close", chord: KeyChord(.escape)),
        ]),
    ]
}

/// A `SettingsContext` made of fakes, with its own preferences: nothing reaches the Keychain, the
/// clipboard, the browser or the system's login items.
@MainActor
final class SettingsFixture {
    let defaults = EphemeralDefaults()
    let config: ConfigStore
    let settings: SettingsModel
    let vault: FakeVault
    let hotKeys: HotKeyCenter
    let activation: ActivationShortcut
    let launchAtLogin: LaunchAtLoginModel
    let context: SettingsContext
    let model: SettingsWindowModel

    /// - Parameters:
    ///   - registersShortcut: Registers ⌃⌥P as the global shortcut, as on a first launch.
    ///   - hotKeys: Shared between fixtures that register the shortcut: one process can hold ⌃⌥P
    ///     only once.
    init(vault: FakeVault = FakeVault(), registersShortcut: Bool = false, hotKeys: HotKeyCenter = HotKeyCenter()) {
        self.hotKeys = hotKeys
        config = ConfigStore(defaults: defaults.defaults)
        settings = SettingsModel(store: config)
        self.vault = vault
        activation = ActivationShortcut(config: config, hotKeys: hotKeys)
        launchAtLogin = LaunchAtLoginModel(service: FakeSettingsLoginItems())
        model = SettingsWindowModel(config: config, shortcutReference: SettingsSamples.shortcutReference)
        context = SettingsContext(
            settings: settings,
            vault: vault,
            catalog: ModelCatalogStore(),
            targets: SettingsSamples.targets,
            launchAtLogin: launchAtLogin,
            shortcut: ShortcutFieldModel(
                activation: activation,
                recorder: ShortcutRecorder(hotKeys: hotKeys),
                isAvailable: { _ in true }
            ),
            updates: UpdateController(isDebugBuild: true, isUpdatableLocation: false, activator: FakeActivator()),
            version: AppVersion(name: "Afino", version: "2.0.0", build: "7"),
            readClipboard: { nil },
            clearHistory: { true },
            openURL: { _ in }
        )
        if registersShortcut {
            // Registering consults the main menu, so the application object has to exist.
            _ = NSApplication.shared
            // ⌃⌥P, held only for the life of this fixture's `HotKeyCenter`.
            config.set(JSONConfigValue(ActivationShortcutDefaults.primary), for: .activationShortcut)
            activation.start {}
        }
    }
}
