import PICore
import PIProviders

/// The model chips of Settings › Engine.
enum PresetChoice: String, CaseIterable, Hashable, Sendable {
    case quality
    case balanced
    case fast
    case custom

    var title: String {
        switch self {
        case .quality: SettingsStrings.text("settings.engine.preset.quality")
        case .balanced: SettingsStrings.text("settings.engine.preset.balanced")
        case .fast: SettingsStrings.text("settings.engine.preset.fast")
        case .custom: SettingsStrings.text("settings.engine.preset.custom")
        }
    }
}

/// One row of the custom model picker: a model the catalog knows, or "Other model" for an id the
/// user types.
enum ModelChoice: Hashable, Sendable {
    case entry(String)
    case other
}

/// A provider chip: disabled while the provider has no key that can be used, unless it is the one
/// chosen (the choice stays visible even when its key goes missing).
struct ProviderOption: Hashable, Sendable {
    let provider: ProviderID
    let isEnabled: Bool
}

/// What Settings › Engine offers, derived from the preset, the provider and the catalog. Pure, so
/// every combination can be tested without a window.
enum EngineOptions {
    /// Chip order: the slowest and best first, Custom last.
    static let presetChoices: [PresetChoice] = [.quality, .balanced, .fast, .custom]
    /// The efforts Settings offers for a custom model, when the model accepts them.
    static let effortChoices: [Effort] = [.low, .medium, .high]

    static func choice(for preset: EnginePreset) -> PresetChoice {
        switch preset {
        case .quality: .quality
        case .balanced: .balanced
        case .fast: .fast
        case .custom: .custom
        }
    }

    /// The preset a chip selects. Custom starts from whatever runs now, so choosing it changes
    /// nothing until the user picks another model or effort; choosing it again keeps the custom
    /// model already set.
    static func preset(for choice: PresetChoice, current: EnginePreset, provider: ProviderID) -> EnginePreset {
        switch choice {
        case .quality: return .quality
        case .balanced: return .balanced
        case .fast: return .fast
        case .custom:
            if case .custom = current { return current }
            let selection = ModelCatalog.selection(for: current, provider: provider)
            return .custom(model: selection.model, effort: selection.effort)
        }
    }

    /// The model id the preset runs on `provider`, as shown under the chips.
    static func resolvedModelID(for preset: EnginePreset, provider: ProviderID) -> String {
        ModelCatalog.selection(for: preset, provider: provider).model
    }

    /// The effort chips for a model: Low, Medium and High, limited to those it accepts.
    static func effortOptions(for capabilities: ModelCapabilities) -> [Effort] {
        effortChoices.filter(capabilities.supportedEfforts.contains)
    }

    /// The effort chips for what `preset` runs on `provider`.
    static func effortOptions(for preset: EnginePreset, provider: ProviderID) -> [Effort] {
        effortOptions(for: ModelCatalog.selection(for: preset, provider: provider).capabilities)
    }

    /// The effort the request will be sent with (the chip shown as chosen).
    static func selectedEffort(for preset: EnginePreset, provider: ProviderID) -> Effort? {
        ModelCatalog.selection(for: preset, provider: provider).effort
    }

    /// A custom preset with another effort; any other preset is returned unchanged.
    static func preset(_ preset: EnginePreset, settingEffort effort: Effort) -> EnginePreset {
        guard case .custom(let model, _) = preset else { return preset }
        return .custom(model: model, effort: effort)
    }

    /// A custom preset with another model, keeping its effort; any other preset is returned
    /// unchanged.
    static func preset(_ preset: EnginePreset, settingModel model: String) -> EnginePreset {
        guard case .custom(_, let effort) = preset else { return preset }
        return .custom(model: model, effort: effort)
    }

    /// The custom model picker: every model the catalog lists for the provider, then "Other".
    static func modelChoices(entries: [CatalogEntry]) -> [ModelChoice] {
        entries.map { .entry($0.model) } + [.other]
    }

    /// The picker row for `model`: its catalog entry, or "Other" for an id the catalog lacks.
    static func modelChoice(for model: String, entries: [CatalogEntry]) -> ModelChoice {
        entries.contains { $0.model == model } ? .entry(model) : .other
    }

    static func providerOptions(selected: ProviderID, state: (ProviderID) -> KeyState) -> [ProviderOption] {
        ProviderID.allCases.map { provider in
            ProviderOption(provider: provider, isEnabled: provider == selected || state(provider).isUsable)
        }
    }

    /// The preset after switching provider. A custom model that belongs to the other provider's
    /// catalog would only fail there, so it becomes the new provider's Balanced model, keeping
    /// the effort; an id neither catalog knows is the user's own and stays.
    static func preset(_ preset: EnginePreset, afterSwitchingFrom old: ProviderID, to new: ProviderID) -> EnginePreset {
        guard case .custom(let model, let effort) = preset, old != new,
              ModelCatalog.entry(for: model, provider: new) == nil,
              ModelCatalog.entry(for: model, provider: old) != nil
        else { return preset }
        return .custom(model: resolvedModelID(for: .balanced, provider: new), effort: effort)
    }
}

extension Effort {
    /// The chip title, for the three efforts Settings offers.
    var settingsTitle: String {
        switch self {
        case .low: SettingsStrings.text("settings.engine.effort.low")
        case .medium: SettingsStrings.text("settings.engine.effort.medium")
        case .high: SettingsStrings.text("settings.engine.effort.high")
        case .none, .xhigh, .max: rawValue
        }
    }
}
