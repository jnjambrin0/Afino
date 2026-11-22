import Foundation
import Observation
import PIFoundation
import PIPrompts
import PIProviders

/// Which target a new prompt starts with.
public nonisolated enum DefaultTarget: Codable, Sendable, Hashable {
    /// Whatever was used last time.
    case lastUsed
    /// Always this pack.
    case fixed(id: String)
}

/// The appearance the user chose for the whole app; `system` follows macOS.
public nonisolated enum AppearanceSetting: String, Codable, Sendable, CaseIterable, ConfigValue {
    case system, light, dark
}

extension ConfigKey where Value == String {
    static let engineProvider = ConfigKey("engineProvider", default: ProviderID.anthropic.rawValue)
    static let lastTargetID = ConfigKey("lastTargetID", default: "")
    static let customInstructions = ConfigKey("customInstructions", default: "")
}

extension ConfigKey where Value == Bool {
    static let customInstructionsEnabled = ConfigKey("customInstructionsEnabled", default: true)
    static let historyEnabled = ConfigKey("historyEnabled", default: true)
    static let onboardingCompleted = ConfigKey("onboardingCompleted", default: false)
    static let legacyCleanupDone = ConfigKey("legacyCleanupDone", default: false)
}

extension ConfigKey where Value == JSONConfigValue<EnginePreset> {
    static let enginePreset = ConfigKey("enginePreset", default: JSONConfigValue(EnginePreset.default))
}

extension ConfigKey where Value == JSONConfigValue<DefaultTarget> {
    static let defaultTarget = ConfigKey("defaultTarget", default: JSONConfigValue(DefaultTarget.lastUsed))
}

extension ConfigKey where Value == OutputLanguage {
    static let outputLanguage = ConfigKey("outputLanguage", default: OutputLanguage.matchDraft)
}

extension ConfigKey where Value == AppearanceSetting {
    static let appearance = ConfigKey("appearance", default: AppearanceSetting.system)
}

/// Everything the user can set, backed by `ConfigStore`: only what they changed is stored, so a
/// default (a preset's model, say) can change in a later version without migrating anything.
@Observable
public final class SettingsModel {
    @ObservationIgnored private let store: ConfigStore

    /// Which provider's API rewrites the prompts.
    public var provider: ProviderID {
        didSet { store.set(provider.rawValue, for: .engineProvider) }
    }

    /// The engine preset, resolved per provider by `engineSelection`.
    public var preset: EnginePreset {
        didSet { store.set(JSONConfigValue(preset), for: .enginePreset) }
    }

    /// Which target a new prompt starts with.
    public var defaultTarget: DefaultTarget {
        didSet { store.set(JSONConfigValue(defaultTarget), for: .defaultTarget) }
    }

    /// The target used most recently; empty until one is chosen.
    public var lastTargetID: String {
        didSet { store.set(lastTargetID, for: .lastTargetID) }
    }

    /// The text of Settings › Instructions, kept even while switched off.
    public var customInstructions: String {
        didSet { store.set(customInstructions, for: .customInstructions) }
    }

    /// Whether the instructions are sent.
    public var customInstructionsEnabled: Bool {
        didSet { store.set(customInstructionsEnabled, for: .customInstructionsEnabled) }
    }

    /// The language the improved prompt is written in.
    public var outputLanguage: OutputLanguage {
        didSet { store.set(outputLanguage, for: .outputLanguage) }
    }

    /// Whether finished prompts are saved to the history.
    public var historyEnabled: Bool {
        didSet { store.set(historyEnabled, for: .historyEnabled) }
    }

    /// The app's appearance: follow the system, or always light or dark.
    public var appearance: AppearanceSetting {
        didSet { store.set(appearance, for: .appearance) }
    }

    /// Whether the welcome window has been completed.
    public var onboardingCompleted: Bool {
        didSet { store.set(onboardingCompleted, for: .onboardingCompleted) }
    }

    /// Whether `LegacyCleanup` has finished, so it is not run again.
    public var legacyCleanupDone: Bool {
        didSet { store.set(legacyCleanupDone, for: .legacyCleanupDone) }
    }

    public init(store: ConfigStore) {
        self.store = store
        provider = ProviderID(rawValue: store.value(for: .engineProvider)) ?? .anthropic
        preset = store.value(for: .enginePreset).value
        defaultTarget = store.value(for: .defaultTarget).value
        lastTargetID = store.value(for: .lastTargetID)
        customInstructions = store.value(for: .customInstructions)
        customInstructionsEnabled = store.value(for: .customInstructionsEnabled)
        outputLanguage = store.value(for: .outputLanguage)
        historyEnabled = store.value(for: .historyEnabled)
        appearance = store.value(for: .appearance)
        onboardingCompleted = store.value(for: .onboardingCompleted)
        legacyCleanupDone = store.value(for: .legacyCleanupDone)
    }

    /// The preset resolved for the chosen provider: model, effort and what the model supports.
    public var engineSelection: EngineSelection {
        ModelCatalog.selection(for: preset, provider: provider)
    }

    /// What the prompt engine needs to know about the user's standing preferences.
    public var promptPreferences: PromptPreferences {
        PromptPreferences(
            customInstructions: customInstructions,
            customInstructionsEnabled: customInstructionsEnabled,
            language: outputLanguage
        )
    }

    /// The target a fresh prompt starts with, as a pack id that may or may not still exist
    /// (`TargetPackLibrary.pack(for:)` falls back to the first pack).
    public var initialTargetID: String? {
        switch defaultTarget {
        case .fixed(let id): id
        case .lastUsed: lastTargetID.isEmpty ? nil : lastTargetID
        }
    }
}
