import Foundation
import PIProviders

/// US dollars per million tokens.
struct ModelPrice: Sendable, Hashable {
    var input: Double
    var output: Double
}

/// Tokens one request is expected to use, for the cost shown before a run.
struct RequestEstimate: Sendable, Hashable {
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    /// Judge requests are listed apart from engine requests to the same model.
    var isJudge = false
}

/// The estimate for one model (and role): how many requests and what they should cost.
struct CostLine: Sendable, Hashable {
    var model: String
    var isJudge = false
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    /// Nil when the model is not in the price table.
    var cost: Double?
}

/// Rough costs from a small built-in price table. Estimates ignore caching discounts, so they
/// err on the high side; costs from reported usage apply them.
enum CostEstimator {
    /// List prices by model id. A model without an entry shows its cost as "n/a", so every model
    /// a configuration or the judge uses has one; update the table when a provider changes prices.
    static let prices: [String: ModelPrice] = [
        "claude-opus-5-5": ModelPrice(input: 4, output: 20),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10),
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50),
        "gpt-6.2-astra": ModelPrice(input: 8, output: 40),
        "gpt-6.2-sol": ModelPrice(input: 2, output: 10),
        "gpt-6.1-terra": ModelPrice(input: 1, output: 5),
        "gpt-6-luna": ModelPrice(input: 0.10, output: 0.50),
    ]

    /// Cache reads cost a tenth of fresh input; Anthropic cache writes cost 1.25×.
    static let cacheReadMultiplier = 0.1
    static let cacheWriteMultiplier = 1.25

    /// The usual rough rule: four characters to a token.
    static func estimatedTokens(characters: Int) -> Int {
        (max(0, characters) + 3) / 4
    }

    /// Extra output tokens spent thinking, by effort.
    static func reasoningAllowance(effort: Effort?, thinkingDisabled: Bool) -> Int {
        guard !thinkingDisabled else { return 0 }
        switch effort {
        case .none?: return 0
        case .low?: return 300
        case .medium?, nil: return 1_000
        case .high?: return 3_000
        case .xhigh?: return 6_000
        case .max?: return 10_000
        }
    }

    /// Visible output tokens for a rewrite of `draft`: a little longer than the draft, within
    /// 150–2,500.
    static func estimatedOutputTokens(forDraft draft: String) -> Int {
        let draftTokens = estimatedTokens(characters: draft.count)
        return min(max(draftTokens * 13 / 10 + 150, 150), 2_500)
    }

    /// The list-price cost of the tokens; nil for a model without a price.
    static func cost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let price = prices[model] else { return nil }
        return (Double(inputTokens) * price.input + Double(outputTokens) * price.output) / 1_000_000
    }

    /// The cost of a finished request from the usage the provider reported. Anthropic counts
    /// cache reads and writes apart from `input_tokens`; OpenAI counts cached tokens inside it.
    static func actualCost(model: String, provider: ProviderID, usage: UsageRecord) -> Double? {
        guard let price = prices[model] else { return nil }
        let input = Double(usage.inputTokens ?? 0)
        let cacheRead = Double(usage.cacheReadInputTokens ?? 0)
        let cacheWrite = Double(usage.cacheCreationInputTokens ?? 0)
        let output = Double(usage.outputTokens ?? 0)
        let inputCost: Double
        switch provider {
        case .anthropic:
            inputCost = input * price.input + cacheRead * price.input * cacheReadMultiplier
                + cacheWrite * price.input * cacheWriteMultiplier
        case .openai:
            inputCost = max(0, input - cacheRead) * price.input + cacheRead * price.input * cacheReadMultiplier
        }
        return (inputCost + output * price.output) / 1_000_000
    }

    /// Groups estimates by model and role: engine lines first, then judge lines, each in
    /// first-seen order.
    static func lines(for estimates: [RequestEstimate]) -> [CostLine] {
        struct Key: Hashable {
            var model: String
            var isJudge: Bool
        }
        var order: [Key] = []
        var lines: [Key: CostLine] = [:]
        for estimate in estimates {
            let key = Key(model: estimate.model, isJudge: estimate.isJudge)
            var line = lines[key] ?? {
                order.append(key)
                return CostLine(model: estimate.model, isJudge: estimate.isJudge, requests: 0, inputTokens: 0, outputTokens: 0, cost: 0)
            }()
            line.requests += 1
            line.inputTokens += estimate.inputTokens
            line.outputTokens += estimate.outputTokens
            lines[key] = line
        }
        let sorted = order.filter { !$0.isJudge } + order.filter(\.isJudge)
        return sorted.compactMap { key in
            guard var line = lines[key] else { return nil }
            line.cost = cost(model: key.model, inputTokens: line.inputTokens, outputTokens: line.outputTokens)
            return line
        }
    }

    /// "$0.42", "$12.30", "<$0.01".
    static func format(_ cost: Double?) -> String {
        guard let cost else { return "n/a" }
        if cost > 0, cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
