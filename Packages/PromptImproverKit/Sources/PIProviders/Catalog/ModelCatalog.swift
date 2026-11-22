import Foundation

/// What Afino may send to a model.
public struct ModelCapabilities: Sendable, Hashable, Codable {
    /// The efforts the model accepts, lowest first.
    public var supportedEfforts: [Effort]
    /// The effort Afino uses for this model unless told otherwise; nil sends none.
    public var defaultEffort: Effort?
    /// The model's ceiling for output tokens; requests are clamped to it.
    public var maxOutputTokens: Int
    /// Anthropic only: whether to ask for server-side fallback on a refusal.
    public var serverSideFallback: Bool
    /// Anthropic only: whether `thinking: {type: "disabled"}` is accepted.
    public var supportsThinkingDisabled: Bool

    public init(
        supportedEfforts: [Effort],
        defaultEffort: Effort?,
        maxOutputTokens: Int,
        serverSideFallback: Bool,
        supportsThinkingDisabled: Bool
    ) {
        self.supportedEfforts = supportedEfforts
        self.defaultEffort = defaultEffort
        self.maxOutputTokens = maxOutputTokens
        self.serverSideFallback = serverSideFallback
        self.supportsThinkingDisabled = supportsThinkingDisabled
    }

    /// For a model Afino knows nothing about (a custom id, or one only the provider's
    /// list names): the three common efforts, no fallback, thinking left on, a modest ceiling.
    public static let conservative = ModelCapabilities(
        supportedEfforts: [.low, .medium, .high],
        defaultEffort: .medium,
        maxOutputTokens: ModelCatalog.minimumOutputTokens,
        serverSideFallback: false,
        supportsThinkingDisabled: false
    )

    /// `effort` if the model accepts it, else the model's default.
    public func resolvedEffort(_ effort: Effort?) -> Effort? {
        guard let effort else { return defaultEffort }
        return supportedEfforts.contains(effort) ? effort : defaultEffort
    }
}

/// One model in the engine picker.
public struct CatalogEntry: Sendable, Hashable, Identifiable {
    /// The provider that serves the model.
    public var provider: ProviderID
    /// The API model id.
    public var model: String
    /// The name the picker shows; the model id when nothing better is known.
    public var displayName: String
    /// What may be sent to the model.
    public var capabilities: ModelCapabilities
    /// Whether Afino ships metadata for it (as opposed to learning it from the provider).
    public var isCurated: Bool
    /// False for a curated model the provider's list didn't include: the key can't use it.
    public var isAvailable: Bool

    /// `provider/model`, unique across providers.
    public var id: String { "\(provider.rawValue)/\(model)" }

    public init(provider: ProviderID, model: String, displayName: String, capabilities: ModelCapabilities, isCurated: Bool = true, isAvailable: Bool = true) {
        self.provider = provider
        self.model = model
        self.displayName = displayName
        self.capabilities = capabilities
        self.isCurated = isCurated
        self.isAvailable = isAvailable
    }
}

/// The ready-made engine settings, plus a model of the person's choosing. What each preset runs
/// on each provider is in `ModelCatalog.presets`.
public enum EnginePreset: Sendable, Hashable, Codable {
    /// Speed first.
    case fast
    /// The everyday default.
    case balanced
    /// Quality first.
    case quality
    /// Any model id; a nil effort leaves it to the model's default.
    case custom(model: String, effort: Effort?)

    /// The preset a new install starts with.
    public static let `default`: EnginePreset = .balanced
}

/// A preset resolved for one provider: everything an `EngineRequest` needs besides the text.
public struct EngineSelection: Sendable, Hashable {
    /// The provider the preset was resolved for.
    public var provider: ProviderID
    /// The API model id.
    public var model: String
    /// The effort to send, already checked against the model's `capabilities`.
    public var effort: Effort?
    /// Anthropic only, and only for a model that accepts it.
    public var thinkingDisabled: Bool
    /// Anthropic only, and only for a model the catalog marks for it.
    public var serverSideFallback: Bool
    /// What the model accepts, which also caps the output budget.
    public var capabilities: ModelCapabilities

    public init(provider: ProviderID, model: String, effort: Effort?, thinkingDisabled: Bool, serverSideFallback: Bool, capabilities: ModelCapabilities) {
        self.provider = provider
        self.model = model
        self.effort = effort
        self.thinkingDisabled = thinkingDisabled
        self.serverSideFallback = serverSideFallback
        self.capabilities = capabilities
    }
}

/// The models Afino knows, the presets, and how to combine them with what a key can use.
public enum ModelCatalog {
    /// The smallest output budget a request gets, however short the draft.
    public static let minimumOutputTokens = 16_000
    /// The largest output budget a request gets, however long the draft.
    public static let maximumOutputTokens = 32_000

    private static let claudeEfforts: [Effort] = [.low, .medium, .high, .xhigh, .max]
    private static let gptEfforts: [Effort] = [.low, .medium, .high, .xhigh, .max]
    private static let gptEffortsWithNone: [Effort] = [.none, .low, .medium, .high, .xhigh, .max]

    /// Curated metadata. Output ceilings above 32,000 only matter as upper bounds, since requests
    /// never ask for more than `maximumOutputTokens`.
    public static let curated: [CatalogEntry] = [
        claude("claude-opus-5-5", "Claude Opus 5.5", effort: .medium, maxOutput: 128_000, fallback: true, thinkingOff: false),
        claude("claude-sonnet-5-5", "Claude Sonnet 5.5", effort: .low, maxOutput: 128_000, fallback: true, thinkingOff: false),
        claude("claude-haiku-5-5", "Claude Haiku 5.5", effort: .low, maxOutput: 64_000, fallback: false, thinkingOff: true),
        claude("claude-fable-5-2", "Claude Fable 5.2", effort: .medium, maxOutput: 128_000, fallback: true, thinkingOff: false),
        gpt("gpt-6.2-astra", "GPT-6.2 Astra", efforts: gptEfforts, effort: .medium),
        gpt("gpt-6.2-sol", "GPT-6.2 Sol", efforts: gptEfforts, effort: .low),
        gpt("gpt-6.1-terra", "GPT-6.1 Terra", efforts: gptEffortsWithNone, effort: .low),
        gpt("gpt-6-luna", "GPT-6 Luna", efforts: gptEffortsWithNone, effort: .none),
    ]

    /// What one preset runs on one provider.
    public struct PresetSetting: Sendable, Hashable {
        /// The API model id.
        public var model: String
        /// The effort to ask for, before it is checked against the model's capabilities.
        public var effort: Effort
        /// Whether to ask for `thinking: {type: "disabled"}` (Anthropic only).
        public var thinkingDisabled: Bool
    }

    /// The presets as data: model, effort and whether thinking is turned off, per provider.
    public static let presets: [EnginePreset: [ProviderID: PresetSetting]] = [
        .fast: [
            .anthropic: PresetSetting(model: "claude-haiku-5-5", effort: .low, thinkingDisabled: true),
            .openai: PresetSetting(model: "gpt-6-luna", effort: .none, thinkingDisabled: false),
        ],
        .balanced: [
            .anthropic: PresetSetting(model: "claude-sonnet-5-5", effort: .low, thinkingDisabled: false),
            .openai: PresetSetting(model: "gpt-6.2-sol", effort: .low, thinkingDisabled: false),
        ],
        .quality: [
            .anthropic: PresetSetting(model: "claude-opus-5-5", effort: .medium, thinkingDisabled: false),
            .openai: PresetSetting(model: "gpt-6.2-astra", effort: .medium, thinkingDisabled: false),
        ],
    ]

    /// The curated models of one provider, in picker order.
    public static func curated(for provider: ProviderID) -> [CatalogEntry] {
        curated.filter { $0.provider == provider }
    }

    /// The curated entry for `model`, or nil for a model the catalog does not know.
    public static func entry(for model: String, provider: ProviderID) -> CatalogEntry? {
        curated.first { $0.provider == provider && $0.model == model }
    }

    /// The curated capabilities of `model`, or conservative ones for a model not in the catalog.
    public static func capabilities(for model: String, provider: ProviderID) -> ModelCapabilities {
        entry(for: model, provider: provider)?.capabilities ?? .conservative
    }

    /// What `preset` runs on `provider`. A custom model gets its curated metadata when it has
    /// some, and conservative capabilities (no fallback, thinking on) when it doesn't.
    public static func selection(for preset: EnginePreset, provider: ProviderID) -> EngineSelection {
        let model: String
        let effort: Effort?
        var thinkingDisabled = false
        if case let .custom(customModel, customEffort) = preset {
            model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
            effort = customEffort
        } else if let setting = presets[preset]?[provider] {
            model = setting.model
            effort = setting.effort
            thinkingDisabled = setting.thinkingDisabled
        } else {
            return selection(for: .default, provider: provider)
        }
        let capabilities = capabilities(for: model, provider: provider)
        let isAnthropic = provider == .anthropic
        return EngineSelection(
            provider: provider,
            model: model,
            effort: capabilities.resolvedEffort(effort),
            thinkingDisabled: isAnthropic && thinkingDisabled && capabilities.supportsThinkingDisabled,
            serverSideFallback: isAnthropic && capabilities.serverSideFallback,
            capabilities: capabilities
        )
    }

    /// The curated entries for `provider` combined with the models its list returned. Curated
    /// metadata wins; curated models missing from `remote` are kept but marked unavailable;
    /// models only `remote` names follow, with the provider's own hints where it gave them and
    /// conservative capabilities otherwise.
    public static func merge(curated: [CatalogEntry] = ModelCatalog.curated, remote: [RemoteModel], provider: ProviderID) -> [CatalogEntry] {
        let remoteIDs = Set(remote.map(\.id))
        let known = curated.filter { $0.provider == provider }
        var entries = known.map { entry in
            var entry = entry
            entry.isAvailable = remoteIDs.contains(entry.model)
            return entry
        }
        let knownIDs = Set(known.map(\.model))
        var seen = knownIDs
        for model in remote where !seen.contains(model.id) {
            seen.insert(model.id)
            entries.append(CatalogEntry(
                provider: provider,
                model: model.id,
                displayName: model.displayName ?? model.id,
                capabilities: capabilities(learnedFrom: model, provider: provider),
                isCurated: false,
                isAvailable: true
            ))
        }
        return entries
    }

    /// Conservative capabilities, narrowed or widened by what the provider reported.
    static func capabilities(learnedFrom model: RemoteModel, provider: ProviderID) -> ModelCapabilities {
        var capabilities = ModelCapabilities.conservative
        if let efforts = model.supportedEfforts {
            capabilities.supportedEfforts = efforts
            capabilities.defaultEffort = efforts.contains(.medium) ? .medium : efforts.first
        }
        if let maxOutput = model.maxOutputTokens, maxOutput > 0 {
            capabilities.maxOutputTokens = maxOutput
        }
        if provider == .anthropic, let thinkingOff = model.supportsThinkingDisabled {
            capabilities.supportsThinkingDisabled = thinkingOff
        }
        return capabilities
    }

    /// The output budget for a draft of `characters` characters: twice its estimated tokens
    /// (about three characters each) plus 4,000, between 16,000 and 32,000.
    public static func maxOutputTokens(forInputCharacters characters: Int) -> Int {
        let estimate = 2 * (max(0, characters) / 3) + 4_000
        return min(max(estimate, minimumOutputTokens), maximumOutputTokens)
    }

    /// `maxOutputTokens(forInputCharacters:)`, never above what the model allows.
    public static func maxOutputTokens(forInputCharacters characters: Int, capabilities: ModelCapabilities) -> Int {
        min(maxOutputTokens(forInputCharacters: characters), capabilities.maxOutputTokens)
    }

    private static func claude(_ model: String, _ name: String, effort: Effort, maxOutput: Int, fallback: Bool, thinkingOff: Bool) -> CatalogEntry {
        CatalogEntry(
            provider: .anthropic,
            model: model,
            displayName: name,
            capabilities: ModelCapabilities(
                supportedEfforts: claudeEfforts,
                defaultEffort: effort,
                maxOutputTokens: maxOutput,
                serverSideFallback: fallback,
                supportsThinkingDisabled: thinkingOff
            )
        )
    }

    private static func gpt(_ model: String, _ name: String, efforts: [Effort], effort: Effort) -> CatalogEntry {
        CatalogEntry(
            provider: .openai,
            model: model,
            displayName: name,
            capabilities: ModelCapabilities(
                supportedEfforts: efforts,
                defaultEffort: effort,
                maxOutputTokens: 128_000,
                serverSideFallback: false,
                supportsThinkingDisabled: false
            )
        )
    }
}
