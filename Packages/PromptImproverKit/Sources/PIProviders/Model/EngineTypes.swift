import Foundation

/// The API a prompt is rewritten with.
public enum ProviderID: String, Sendable, Codable, CaseIterable, Hashable {
    case anthropic
    case openai

    /// The company name, for messages such as "Anthropic rejected your API key".
    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        }
    }
}

/// How much work the model puts into its answer. Anthropic sends it as `output_config.effort`,
/// OpenAI as `reasoning.effort`. Anthropic has no `none`: it is sent as no effort at all.
public enum Effort: String, Sendable, Codable, CaseIterable, Hashable {
    case none
    case low
    case medium
    case high
    case xhigh
    case max
}

/// One request to rewrite a prompt: the model and how to run it, the stable system text and the
/// conversation so far.
public struct EngineRequest: Sendable, Hashable {
    /// One message of the conversation.
    public enum Turn: Sendable, Hashable {
        case user(String)
        case assistant(String)
    }

    /// The API model id.
    public var model: String
    /// Nil leaves the effort to the model's default.
    public var effort: Effort?
    /// Anthropic only: sends `thinking: {type: "disabled"}`. Ignored by OpenAI.
    public var thinkingDisabled: Bool
    /// The most output tokens the answer may use (`max_tokens`, `max_output_tokens`).
    public var maxOutputTokens: Int
    /// The system prompt in pieces, the most stable first. Anthropic's cache breakpoint goes on
    /// the last block; OpenAI receives them joined by a blank line in one `developer` item.
    public var systemBlocks: [String]
    /// The conversation; the last turn is the user's. A trailing assistant turn is never sent.
    public var turns: [Turn]
    /// Anthropic only: asks for server-side fallback on a refusal (set from the model catalog).
    public var serverSideFallback: Bool

    public init(
        model: String,
        effort: Effort? = nil,
        thinkingDisabled: Bool = false,
        maxOutputTokens: Int = ModelCatalog.minimumOutputTokens,
        systemBlocks: [String] = [],
        turns: [Turn],
        serverSideFallback: Bool = false
    ) {
        self.model = model
        self.effort = effort
        self.thinkingDisabled = thinkingDisabled
        self.maxOutputTokens = maxOutputTokens
        self.systemBlocks = systemBlocks
        self.turns = turns
        self.serverSideFallback = serverSideFallback
    }

    /// A request that runs as `selection` says.
    public init(selection: EngineSelection, maxOutputTokens: Int, systemBlocks: [String], turns: [Turn]) {
        self.init(
            model: selection.model,
            effort: selection.effort,
            thinkingDisabled: selection.thinkingDisabled,
            maxOutputTokens: maxOutputTokens,
            systemBlocks: systemBlocks,
            turns: turns,
            serverSideFallback: selection.serverSideFallback
        )
    }
}

/// What a running request reports, in order: optionally `.retrying`, then `.started`, any
/// `.thinking` and `.textDelta`, and one `.finished`. A retry (only ever before the first
/// `.textDelta`) starts the sequence again with another `.started`. Errors end the stream by
/// throwing an `EngineFailure`.
public enum EngineEvent: Sendable, Equatable {
    /// Attempt number `attempt` (2 or later) begins after waiting `after`.
    case retrying(attempt: Int, after: Duration, reason: RetryReason)
    /// The provider accepted the request and began answering.
    case started(servedModel: String, requestID: String?)
    /// The model is thinking before it writes.
    case thinking
    /// More of the answer, to append to the text before it.
    case textDelta(String)
    /// The answer ended.
    case finished(FinishReason, usage: TokenUsage?)
}

/// Why an answer ended.
public enum FinishReason: Sendable, Equatable, Hashable {
    case complete
    /// Cut off at the output-token limit.
    case truncated
    /// The model or a safety classifier declined. `category` is the provider's label for the
    /// policy area when it gives one (Anthropic's `stop_details.category`, OpenAI's
    /// `content_filter`).
    case refused(category: String?)
}

/// Why a request is being sent again.
public enum RetryReason: Sendable, Equatable, Hashable {
    case rateLimited
    case overloaded
    case serverError(status: Int)
    /// The request timed out before any text arrived.
    case timedOut
    /// The connection dropped or could not be made.
    case network
    /// The provider said to retry (`x-should-retry: true`) for an error that isn't retried by default.
    case requestedByServer
}

/// Token counts the provider reported, when it reported them.
public struct TokenUsage: Sendable, Equatable, Hashable {
    /// Input tokens, including the cached ones on OpenAI and excluding them on Anthropic.
    public var inputTokens: Int?
    /// Output tokens, reasoning included.
    public var outputTokens: Int?
    /// Input tokens read from the prompt cache.
    public var cacheReadInputTokens: Int?
    /// Input tokens written to the prompt cache (Anthropic only).
    public var cacheCreationInputTokens: Int?
    /// Output tokens spent on reasoning (OpenAI only).
    public var reasoningTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.reasoningTokens = reasoningTokens
    }

    var isEmpty: Bool { self == TokenUsage() }
    var nonEmpty: TokenUsage? { isEmpty ? nil : self }
}

/// A model a key can use, as the provider's `GET /v1/models` lists it. The optional hints are
/// filled only where the provider reports them (Anthropic does; OpenAI lists ids only).
public struct RemoteModel: Sendable, Hashable, Codable, Identifiable {
    /// The API model id.
    public var id: String
    /// The provider's name for the model (Anthropic only).
    public var displayName: String?
    /// The model's output ceiling (Anthropic only).
    public var maxOutputTokens: Int?
    /// Nil when the provider did not say; empty when it said the model takes no effort setting.
    public var supportedEfforts: [Effort]?
    /// Whether `thinking: {type: "disabled"}` is accepted (Anthropic only).
    public var supportsThinkingDisabled: Bool?

    public init(
        id: String,
        displayName: String? = nil,
        maxOutputTokens: Int? = nil,
        supportedEfforts: [Effort]? = nil,
        supportsThinkingDisabled: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.maxOutputTokens = maxOutputTokens
        self.supportedEfforts = supportedEfforts
        self.supportsThinkingDisabled = supportsThinkingDisabled
    }
}
