import Foundation
import PIProviders
import Testing
@testable import PromptEval

/// Cost estimation and what each mode plans to send.
struct CostAndPlanTests {
    @Test
    func thePriceTableHoldsTheListedPricesForEveryConfiguredModel() {
        let expected: [String: (Double, Double)] = [
            "claude-opus-5-5": (4, 20), "claude-sonnet-5-5": (2, 10), "claude-haiku-5-5": (0.10, 0.50),
            "gpt-6.2-astra": (8, 40), "gpt-6.2-sol": (2, 10), "gpt-6.1-terra": (1, 5), "gpt-6-luna": (0.10, 0.50),
        ]
        #expect(CostEstimator.prices.count == expected.count)
        for (model, (input, output)) in expected {
            #expect(CostEstimator.prices[model] == ModelPrice(input: input, output: output), "\(model)")
        }
        let models = Set((ProviderID.allCases.flatMap(EvalConfiguration.sweepCandidates(for:)) + ProviderID.allCases.flatMap(EvalConfiguration.shippedPresets(for:))).map(\.model))
        #expect(models.isSubset(of: Set(CostEstimator.prices.keys)), "every configuration has a price")
    }

    @Test
    func costFromTokens() throws {
        #expect(CostEstimator.cost(model: "claude-sonnet-5-5", inputTokens: 1_000_000, outputTokens: 1_000_000) == 12)
        let luna = try #require(CostEstimator.cost(model: "gpt-6-luna", inputTokens: 2_000, outputTokens: 1_000))
        #expect(abs(luna - 0.0007) < 1e-12)
        #expect(CostEstimator.cost(model: "unknown-model", inputTokens: 1, outputTokens: 1) == nil)
        #expect(CostEstimator.estimatedTokens(characters: 8) == 2)
        #expect(CostEstimator.estimatedTokens(characters: 9) == 3)
        #expect(CostEstimator.format(12.345) == "$12.35")
        #expect(CostEstimator.format(0.001) == "<$0.01")
        #expect(CostEstimator.format(nil) == "n/a")
    }

    @Test
    func reportedUsageCountsCachesPerProvider() throws {
        // Anthropic: input_tokens excludes cache reads and writes.
        let anthropic = try #require(CostEstimator.actualCost(
            model: "claude-opus-5-5", provider: .anthropic,
            usage: UsageRecord(inputTokens: 100, outputTokens: 1_000, cacheReadInputTokens: 2_000, cacheCreationInputTokens: 1_000)))
        let anthropicInput: Double = 100 * 4 + 2_000 * 4 * 0.1 + 1_000 * 4 * 1.25
        let expectedAnthropic: Double = (anthropicInput + 1_000 * 20) / 1_000_000
        #expect(abs(anthropic - expectedAnthropic) < 1e-12)
        // OpenAI: cached tokens are part of input_tokens.
        let openAI = try #require(CostEstimator.actualCost(
            model: "gpt-6.2-sol", provider: .openai,
            usage: UsageRecord(inputTokens: 3_000, outputTokens: 500, cacheReadInputTokens: 2_000)))
        let openAIInput: Double = 1_000 * 2 + 2_000 * 2 * 0.1
        let expectedOpenAI: Double = (openAIInput + 500 * 10) / 1_000_000
        #expect(abs(openAI - expectedOpenAI) < 1e-12)
    }

    @Test
    func estimatesGroupByModelWithTheJudgeApart() {
        let lines = CostEstimator.lines(for: [
            RequestEstimate(model: "claude-opus-5-5", inputTokens: 1_000, outputTokens: 100),
            RequestEstimate(model: "claude-opus-5-5", inputTokens: 1_000, outputTokens: 100, isJudge: true),
            RequestEstimate(model: "gpt-6-luna", inputTokens: 500, outputTokens: 50),
            RequestEstimate(model: "claude-opus-5-5", inputTokens: 1_000, outputTokens: 100),
        ])
        #expect(lines.map(\.model) == ["claude-opus-5-5", "gpt-6-luna", "claude-opus-5-5"])
        #expect(lines.map(\.isJudge) == [false, false, true])
        #expect(lines[0].requests == 2)
        #expect(lines[0].inputTokens == 2_000)
        #expect(lines[0].cost == CostEstimator.cost(model: "claude-opus-5-5", inputTokens: 2_000, outputTokens: 200))
    }

    @Test
    func reasoningAllowanceFollowsEffort() {
        #expect(CostEstimator.reasoningAllowance(effort: Effort.none, thinkingDisabled: false) == 0)
        #expect(CostEstimator.reasoningAllowance(effort: .low, thinkingDisabled: true) == 0)
        #expect(CostEstimator.reasoningAllowance(effort: .low, thinkingDisabled: false) < CostEstimator.reasoningAllowance(effort: .medium, thinkingDisabled: false))
        #expect(CostEstimator.estimatedOutputTokens(forDraft: "") == 150, "the floor")
        #expect(CostEstimator.estimatedOutputTokens(forDraft: "??") == 151)
        #expect(CostEstimator.estimatedOutputTokens(forDraft: String(repeating: "x", count: 100_000)) == 2_500)
    }

    @Test
    func smokeIsEightFixturesOnBalancedOnce() throws {
        let plan = try EvalPlan.make(mode: .smoke, providers: [.anthropic, .openai], library: Shipped.fixtures,
                                     fixtureIDs: nil, repetitions: nil, judge: nil)
        #expect(plan.fixtures.count == 8)
        #expect(plan.configurations.map(\.id) == ["anthropic/balanced", "openai/balanced"])
        #expect(plan.repetitions == 1)
        #expect(plan.jobs.count == 16)
        #expect(plan.judge == nil, "smoke does not judge unless asked")
    }

    @Test
    func fullIsEveryFixtureOnEveryPresetThreeTimes() throws {
        let plan = try EvalPlan.make(mode: .full, providers: [.openai], library: Shipped.fixtures,
                                     fixtureIDs: nil, repetitions: nil, judge: nil)
        #expect(plan.fixtures.count == 31)
        #expect(plan.configurations.map(\.id) == ["openai/fast", "openai/balanced", "openai/quality"])
        #expect(plan.jobs.count == 31 * 3 * 3)
        #expect(plan.engineRequestCount == (31 + 2) * 3 * 3, "the two refinements send a second request")
        #expect(plan.judge?.primary == .openAI, "GPT judges when it is the only key")
        #expect(plan.judge?.crossCheck == nil)
    }

    @Test
    func sweepInterleavesCandidatesInTime() throws {
        let plan = try EvalPlan.make(mode: .sweep, providers: [.anthropic, .openai], library: Shipped.fixtures,
                                     fixtureIDs: ["es-email", "img-en"], repetitions: nil, judge: false)
        #expect(plan.configurations.count == 13)
        #expect(plan.repetitions == 3)
        #expect(plan.jobs.count == 2 * 13 * 3)
        #expect(plan.judge == nil)
        // Every configuration appears once before any appears twice.
        let firstRound = plan.jobs.prefix(13).map(\.configuration.id)
        #expect(Set(firstRound).count == 13)
        #expect(plan.jobs.map(\.repetition) == plan.jobs.map(\.repetition).sorted())
        #expect(plan.jobs.map(\.index) == Array(0..<plan.jobs.count))
    }

    @Test
    func optionsOverrideTheModeDefaults() throws {
        let plan = try EvalPlan.make(mode: .smoke, providers: [.anthropic, .openai], library: Shipped.fixtures,
                                     fixtureIDs: ["es-email", "minimal-qq"], repetitions: 2, judge: true)
        #expect(plan.fixtures.map(\.id) == ["es-email", "minimal-qq"])
        #expect(plan.repetitions == 2)
        #expect(plan.judge?.primary == .anthropic)
        #expect(plan.judge?.crossCheck == .openAI)
        #expect(plan.cacheProbeFixture?.id == "minimal-qq", "the cheapest fixture probes the cache")
        #expect(throws: EvalError.unknownFixtures(["nope"])) {
            try EvalPlan.make(mode: .smoke, providers: [.anthropic], library: Shipped.fixtures,
                              fixtureIDs: ["es-email", "nope"], repetitions: nil, judge: nil)
        }
    }

    @Test
    func theEstimateCoversEngineJudgeAndProbeRequests() throws {
        let plan = try EvalPlan.make(mode: .full, providers: [.anthropic, .openai], library: Shipped.fixtures,
                                     fixtureIDs: nil, repetitions: nil, judge: true)
        let estimates = plan.requestEstimates(library: Shipped.packs, composer: Shipped.composer)
        let judge = estimates.filter(\.isJudge)
        #expect(estimates.count - judge.count == plan.engineRequestCount + plan.configurations.count * 2)
        #expect(judge.count == plan.jobs.count + plan.crossCheckCount)
        #expect(Double(plan.crossCheckCount) / Double(plan.jobs.count) > 0.12)
        #expect(Double(plan.crossCheckCount) / Double(plan.jobs.count) < 0.28)
        #expect(estimates.allSatisfy { $0.inputTokens > 0 && $0.outputTokens > 0 })
        let total = CostEstimator.lines(for: estimates).compactMap(\.cost).reduce(0, +)
        #expect(total > 1 && total < 500, "a sane order of magnitude")
    }

    @Test
    func theCrossCheckSampleIsStable() {
        let setup = JudgeSetup(primary: .anthropic, crossCheck: .openAI)
        let first = (1...200).map { setup.crossChecks(fixtureID: "f\($0)", configurationID: "c", repetition: 1) }
        let second = (1...200).map { setup.crossChecks(fixtureID: "f\($0)", configurationID: "c", repetition: 1) }
        #expect(first == second)
        #expect(JudgeSetup.stableHash("abc") == 0xe71f_a219_0541_574b, "FNV-1a, independent of the process's hash seed")
        #expect(!JudgeSetup(primary: .anthropic, crossCheck: nil).crossChecks(fixtureID: "f", configurationID: "c", repetition: 1))
    }
}
