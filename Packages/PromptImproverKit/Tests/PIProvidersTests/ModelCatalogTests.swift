import Foundation
import Testing
@testable import PIProviders

struct ModelCatalogTests {
    @Test(arguments: [
        (EnginePreset.fast, ProviderID.anthropic, "claude-haiku-5-5", Effort.low, true, false),
        (.balanced, .anthropic, "claude-sonnet-5-5", .low, false, true),
        (.quality, .anthropic, "claude-opus-5-5", .medium, false, true),
        (.fast, .openai, "gpt-6-luna", Effort.none, false, false),
        (.balanced, .openai, "gpt-6.2-sol", .low, false, false),
        (.quality, .openai, "gpt-6.2-astra", .medium, false, false),
    ])
    func presetsResolveAsTabled(_ preset: EnginePreset, _ provider: ProviderID, _ model: String, _ effort: Effort, _ thinkingDisabled: Bool, _ fallback: Bool) {
        let selection = ModelCatalog.selection(for: preset, provider: provider)
        #expect(selection.model == model)
        #expect(selection.effort == effort)
        #expect(selection.thinkingDisabled == thinkingDisabled)
        #expect(selection.serverSideFallback == fallback)
    }

    @Test func balancedIsTheDefault() {
        #expect(EnginePreset.default == .balanced)
    }

    @Test func fallbackIsOnForEveryCuratedClaudeButHaiku() {
        let claude = ModelCatalog.curated(for: .anthropic)
        #expect(claude.map(\.model) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"])
        #expect(claude.filter(\.capabilities.serverSideFallback).map(\.model) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"])
        #expect(claude.filter(\.capabilities.supportsThinkingDisabled).map(\.model) == ["claude-haiku-5-5"])
        #expect(ModelCatalog.curated(for: .openai).allSatisfy { !$0.capabilities.serverSideFallback })
    }

    @Test func onlyTerraAndLunaAcceptNoEffort() {
        let withNone = ModelCatalog.curated(for: .openai).filter { $0.capabilities.supportedEfforts.contains(.none) }.map(\.model)
        #expect(withNone == ["gpt-6.1-terra", "gpt-6-luna"])
        #expect(ModelCatalog.capabilities(for: "gpt-6.2-sol", provider: .openai).supportedEfforts == [.low, .medium, .high, .xhigh, .max])
    }

    @Test func aCustomUnknownModelIsConservative() {
        let selection = ModelCatalog.selection(for: .custom(model: " claude-opus-4-8 ", effort: .high), provider: .anthropic)
        #expect(selection.model == "claude-opus-4-8")
        #expect(selection.effort == .high)
        #expect(!selection.serverSideFallback)
        #expect(!selection.thinkingDisabled)
        #expect(selection.capabilities == .conservative)

        let unsupported = ModelCatalog.selection(for: .custom(model: "gpt-5.2", effort: .max), provider: .openai)
        #expect(unsupported.effort == ModelCapabilities.conservative.defaultEffort)
    }

    @Test func aCustomCuratedModelKeepsItsMetadata() {
        let fable = ModelCatalog.selection(for: .custom(model: "claude-fable-5-2", effort: .high), provider: .anthropic)
        #expect(fable.serverSideFallback)
        #expect(fable.effort == .high)
        let terra = ModelCatalog.selection(for: .custom(model: "gpt-6.1-terra", effort: Effort.none), provider: .openai)
        #expect(terra.effort == Effort.none)
    }

    @Test func mergeKeepsCuratedFirstFlagsMissingOnesAndAppendsTheRest() {
        let remote = [
            RemoteModel(id: "claude-opus-4-8", displayName: "Claude Opus 4.8", maxOutputTokens: 64_000, supportedEfforts: [.low, .medium, .high, .max], supportsThinkingDisabled: true),
            RemoteModel(id: "claude-sonnet-5-5", displayName: "Remote name loses"),
            RemoteModel(id: "claude-haiku-5-5"),
            RemoteModel(id: "claude-opus-5-5"),
            RemoteModel(id: "claude-mystery"),
            RemoteModel(id: "claude-opus-4-8"),
        ]
        let merged = ModelCatalog.merge(remote: remote, provider: .anthropic)
        #expect(merged.map(\.model) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2", "claude-opus-4-8", "claude-mystery"])
        #expect(merged.map(\.isAvailable) == [true, true, true, false, true, true])
        #expect(merged.map(\.isCurated) == [true, true, true, true, false, false])
        #expect(merged[1].displayName == "Claude Sonnet 5.5")
        #expect(merged[1].capabilities.serverSideFallback)

        let learned = merged[4]
        #expect(learned.displayName == "Claude Opus 4.8")
        #expect(learned.capabilities.maxOutputTokens == 64_000)
        #expect(learned.capabilities.supportedEfforts == [.low, .medium, .high, .max])
        #expect(learned.capabilities.supportsThinkingDisabled)
        #expect(!learned.capabilities.serverSideFallback)

        #expect(merged[5].capabilities == .conservative)
        #expect(merged[5].displayName == "claude-mystery")
    }

    @Test func mergeWithAnEmptyListMarksEveryCuratedModelUnavailable() {
        let merged = ModelCatalog.merge(remote: [], provider: .openai)
        #expect(merged.map(\.model) == ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.1-terra", "gpt-6-luna"])
        #expect(merged.allSatisfy { !$0.isAvailable })
    }

    @Test(arguments: [(0, 16_000), (18_000, 16_000), (20_000, 17_332), (30_000, 24_000), (42_000, 32_000), (1_000_000, 32_000), (-5, 16_000)])
    func outputBudgetFollowsTheDraftLength(_ characters: Int, _ expected: Int) {
        #expect(ModelCatalog.maxOutputTokens(forInputCharacters: characters) == expected)
    }

    @Test func outputBudgetNeverExceedsTheModel() {
        var small = ModelCapabilities.conservative
        small.maxOutputTokens = 8_192
        #expect(ModelCatalog.maxOutputTokens(forInputCharacters: 60_000, capabilities: small) == 8_192)
    }

    @Test func aRequestBuiltFromASelectionCarriesItsFlags() {
        let selection = ModelCatalog.selection(for: .fast, provider: .anthropic)
        let request = EngineRequest(selection: selection, maxOutputTokens: 20_000, systemBlocks: ["s"], turns: [.user("u")])
        #expect(request.model == "claude-haiku-5-5")
        #expect(request.thinkingDisabled)
        #expect(!request.serverSideFallback)
        #expect(request.maxOutputTokens == 20_000)
    }

    @Test func presetsRoundTripThroughCodable() throws {
        for preset in [EnginePreset.fast, .balanced, .quality, .custom(model: "gpt-6.1-terra", effort: .low), .custom(model: "x", effort: nil)] {
            let data = try JSONEncoder().encode(preset)
            #expect(try JSONDecoder().decode(EnginePreset.self, from: data) == preset)
        }
    }
}
