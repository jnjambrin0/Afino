import Foundation
import PIProviders

/// The latency targets a preset must meet at p50 on short fixtures.
struct LatencyTarget: Sendable, Hashable, Codable {
    /// Seconds from sending the request to the first text.
    var firstText: Double
    /// Seconds from sending the request to the end of the answer.
    var total: Double
}

/// The three shipped presets, with what the ship gate holds each one to.
enum PresetTier: String, Codable, Sendable, CaseIterable, Comparable {
    case fast
    case balanced
    case quality

    /// The `ModelCatalog` preset this tier gates.
    var enginePreset: EnginePreset {
        switch self {
        case .fast: .fast
        case .balanced: .balanced
        case .quality: .quality
        }
    }

    var latencyTarget: LatencyTarget {
        switch self {
        case .fast: LatencyTarget(firstText: 1.5, total: 4)
        case .balanced: LatencyTarget(firstText: 3, total: 8)
        case .quality: LatencyTarget(firstText: 8, total: 20)
        }
    }

    /// The least mean judge score the gate accepts.
    var minimumMeanOverall: Double {
        switch self {
        case .fast: 3.7
        case .balanced, .quality: 4.0
        }
    }

    static func < (lhs: PresetTier, rhs: PresetTier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One way of running the engine: provider, model, effort and thinking.
///
/// `selection()` resolves it through `ModelCatalog`, exactly as the app resolves a preset or a
/// custom model, so a configuration never sends anything the app would not.
struct EvalConfiguration: Codable, Sendable, Hashable, Identifiable {
    /// `anthropic/balanced` for a shipped preset, `anthropic/claude-opus-5-5/low` for a sweep
    /// candidate.
    var id: String
    var provider: ProviderID
    var model: String
    var effort: Effort?
    /// Anthropic only: sends `thinking: {type: "disabled"}` where the model supports it.
    var thinkingDisabled: Bool
    /// The shipped preset this configuration is identical to, if any. Only these are gated.
    var preset: PresetTier?

    /// "claude-sonnet-5-5 · low" or "claude-haiku-5-5 · low · thinking off".
    var label: String {
        var parts = [model, effort?.rawValue ?? "default effort"]
        if thinkingDisabled { parts.append("thinking off") }
        return parts.joined(separator: " · ")
    }

    /// What `EngineRequest(selection:…)` receives.
    func selection() -> EngineSelection {
        var selection = ModelCatalog.selection(for: .custom(model: model, effort: effort), provider: provider)
        selection.thinkingDisabled = provider == .anthropic && thinkingDisabled
            && selection.capabilities.supportsThinkingDisabled
        return selection
    }

    /// A shipped preset, read from `ModelCatalog` (never restated here).
    static func shipped(_ tier: PresetTier, provider: ProviderID) -> EvalConfiguration {
        let selection = ModelCatalog.selection(for: tier.enginePreset, provider: provider)
        return EvalConfiguration(
            id: "\(provider.rawValue)/\(tier.rawValue)",
            provider: provider,
            model: selection.model,
            effort: selection.effort,
            thinkingDisabled: selection.thinkingDisabled,
            preset: tier
        )
    }

    /// A sweep candidate. It is tagged with the shipped preset it equals, so a sweep also gates
    /// the presets it happens to cover.
    static func candidate(_ provider: ProviderID, _ model: String, _ effort: Effort, thinkingDisabled: Bool = false) -> EvalConfiguration {
        var configuration = EvalConfiguration(
            id: "\(provider.rawValue)/\(model)/\(effort.rawValue)\(thinkingDisabled ? "/no-thinking" : "")",
            provider: provider,
            model: model,
            effort: effort,
            thinkingDisabled: thinkingDisabled,
            preset: nil
        )
        let selection = configuration.selection()
        configuration.preset = PresetTier.allCases.first {
            ModelCatalog.selection(for: $0.enginePreset, provider: provider) == selection
        }
        return configuration
    }

    /// Fast, Balanced and Quality for `provider`.
    static func shippedPresets(for provider: ProviderID) -> [EvalConfiguration] {
        PresetTier.allCases.map { shipped($0, provider: provider) }
    }

    /// The candidates the sweep compares to choose the preset defaults.
    static func sweepCandidates(for provider: ProviderID) -> [EvalConfiguration] {
        switch provider {
        case .anthropic:
            [
                candidate(.anthropic, "claude-haiku-5-5", .low, thinkingDisabled: true),
                candidate(.anthropic, "claude-haiku-5-5", .low),
                candidate(.anthropic, "claude-sonnet-5-5", .low),
                candidate(.anthropic, "claude-sonnet-5-5", .medium),
                candidate(.anthropic, "claude-opus-5-5", .low),
                candidate(.anthropic, "claude-opus-5-5", .medium),
            ]
        case .openai:
            [
                candidate(.openai, "gpt-6-luna", Effort.none),
                candidate(.openai, "gpt-6-luna", .low),
                candidate(.openai, "gpt-6.1-terra", .low),
                candidate(.openai, "gpt-6.2-sol", .low),
                candidate(.openai, "gpt-6.2-sol", .medium),
                candidate(.openai, "gpt-6.2-astra", .low),
                candidate(.openai, "gpt-6.2-astra", .medium),
            ]
        }
    }
}
