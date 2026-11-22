import Foundation
import PIPrompts
import PIProviders
import Testing
@testable import PromptEval

/// The harness sends what the app sends: the same system blocks, turns, model settings and output
/// budget as `ImproveSession.start`.
struct RequestBuildingTests {
    let composer = Shipped.composer
    let library = Shipped.packs

    private func request(_ fixtureID: String, _ configuration: EvalConfiguration, revisedFrom previous: String? = nil) throws -> (EngineRequest, PromptConversation) {
        let fixture = Shipped.fixture(fixtureID)
        let target = try #require(library.pack(withID: fixture.target))
        var conversation = composer.startConversation(draft: fixture.draft, target: target)
        if let previous, let refine = fixture.refine {
            conversation.appendRevision(previousOutput: previous, instruction: refine)
        }
        let request = EvalRequestBuilder.request(for: conversation, target: target, preferences: fixture.promptPreferences,
                                                 selection: configuration.selection(), composer: composer)
        return (request, conversation)
    }

    @Test
    func systemBlocksAreCoreThenPack() throws {
        let configuration = EvalConfiguration.shipped(.balanced, provider: .anthropic)
        let (request, conversation) = try request("es-email", configuration)
        let pack = try #require(library.pack(withID: "claude"))
        #expect(request.systemBlocks.count == 2)
        #expect(request.systemBlocks[0] == composer.core)
        #expect(request.systemBlocks[1].hasPrefix("<target_guidance>"))
        #expect(request.systemBlocks == composer.systemBlocks(for: pack, preferences: PromptPreferences()))
        #expect(request.turns == [.user(conversation.runMessage)])
        #expect(conversation.runMessage.contains("<draft id=\"\(conversation.draftID)\">\n\(Shipped.fixture("es-email").draft)\n</draft id=\"\(conversation.draftID)\">"))
        #expect(conversation.runMessage.hasSuffix("Rewrite this draft as a prompt for Claude (Anthropic). Reply with the prompt only."))
    }

    @Test
    func preferencesAddAThirdBlock() throws {
        let configuration = EvalConfiguration.shipped(.balanced, provider: .openai)
        let (english, _) = try request("es-email-english", configuration)
        #expect(english.systemBlocks.count == 3)
        #expect(english.systemBlocks[2].hasPrefix("<user_preferences>\nWrite the prompt in English regardless of the draft's language."))

        let (noHeadings, _) = try request("en-system-no-headings", configuration)
        #expect(noHeadings.systemBlocks.count == 3)
        #expect(noHeadings.systemBlocks[2] == "<user_preferences>\nNo Markdown headings.\n</user_preferences>")
    }

    @Test
    func aRefinementAddsTheShownOutputAndTheRevisionRequest() throws {
        let configuration = EvalConfiguration.shipped(.fast, provider: .anthropic)
        let shown = "Plan a check-in app for a bouldering gym."
        let (request, conversation) = try request("en-long-messy-refine-shorter", configuration, revisedFrom: shown)
        #expect(request.turns.count == 3)
        #expect(request.turns[0] == .user(conversation.runMessage))
        #expect(request.turns[1] == .assistant(shown))
        guard case .user(let revision) = request.turns[2] else {
            Issue.record("the last turn is not the user's")
            return
        }
        #expect(revision == "<revision_request>\nmás corto\n</revision_request>\n\nApply this to your previous prompt and reply with the complete revised prompt only.")
    }

    @Test
    func modelSettingsAndBudgetComeFromTheCatalog() throws {
        for provider in ProviderID.allCases {
            for tier in PresetTier.allCases {
                let configuration = EvalConfiguration.shipped(tier, provider: provider)
                let selection = ModelCatalog.selection(for: tier.enginePreset, provider: provider)
                let (request, conversation) = try request("en-long-messy", configuration)
                #expect(request.model == selection.model)
                #expect(request.effort == selection.effort)
                #expect(request.thinkingDisabled == selection.thinkingDisabled)
                #expect(request.serverSideFallback == selection.serverSideFallback)
                let budget = ModelCatalog.maxOutputTokens(forInputCharacters: conversation.runMessage.count, capabilities: selection.capabilities)
                #expect(request.maxOutputTokens == budget)
            }
        }
    }

    @Test
    func shippedConfigurationsResolveExactlyLikeThePresets() {
        for provider in ProviderID.allCases {
            for tier in PresetTier.allCases {
                let configuration = EvalConfiguration.shipped(tier, provider: provider)
                #expect(configuration.selection() == ModelCatalog.selection(for: tier.enginePreset, provider: provider), "\(configuration.id)")
                #expect(configuration.preset == tier)
            }
        }
        #expect(EvalConfiguration.shipped(.fast, provider: .anthropic).thinkingDisabled)
        #expect(EvalConfiguration.shipped(.fast, provider: .openai).effort == Effort.none)
    }

    @Test
    func sweepCandidatesAreListedInOrderAndTaggedWithTheirPreset() {
        let anthropic = EvalConfiguration.sweepCandidates(for: .anthropic)
        let openAI = EvalConfiguration.sweepCandidates(for: .openai)
        #expect(anthropic.map(\.id) == [
            "anthropic/claude-haiku-5-5/low/no-thinking", "anthropic/claude-haiku-5-5/low",
            "anthropic/claude-sonnet-5-5/low", "anthropic/claude-sonnet-5-5/medium",
            "anthropic/claude-opus-5-5/low", "anthropic/claude-opus-5-5/medium",
        ])
        #expect(openAI.map(\.id) == [
            "openai/gpt-6-luna/none", "openai/gpt-6-luna/low", "openai/gpt-6.1-terra/low",
            "openai/gpt-6.2-sol/low", "openai/gpt-6.2-sol/medium",
            "openai/gpt-6.2-astra/low", "openai/gpt-6.2-astra/medium",
        ])
        for candidates in [anthropic, openAI] {
            #expect(candidates.compactMap(\.preset).sorted() == PresetTier.allCases, "each preset appears once among the candidates")
        }
        let adaptiveHaiku = anthropic[1]
        #expect(adaptiveHaiku.preset == nil)
        #expect(!adaptiveHaiku.selection().thinkingDisabled)
        #expect(adaptiveHaiku.selection().effort == .low)
        #expect(openAI[0].selection().effort == Effort.none)
    }

    @Test
    func theRunnerSendsTheBuiltRequest() async throws {
        let provider = ScriptedProvider(id: .anthropic) { _ in .text("Redacta un correo para el casero sobre la caldera.") }
        let engine = EvalEngine(library: library, composer: composer, providers: [.anthropic: provider], keys: [.anthropic: APIKey("test-key")])
        let configuration = EvalConfiguration.shipped(.balanced, provider: .anthropic)
        let job = EvalJob(index: 0, fixture: Shipped.fixture("es-email-english"), configuration: configuration, repetition: 1)
        let record = await EvalRunner(engine: engine, judge: nil, concurrency: 1).run(job)

        let sent = try #require(provider.requests.first)
        let pack = try #require(library.pack(withID: "claude"))
        let expected = EvalRequestBuilder.request(
            for: composer.startConversation(draft: job.fixture.draft, target: pack),
            target: pack, preferences: job.fixture.promptPreferences, selection: configuration.selection(), composer: composer)
        #expect(provider.requests.count == 1)
        #expect(sent.systemBlocks == expected.systemBlocks)
        #expect(sent.model == expected.model)
        #expect(sent.effort == expected.effort)
        #expect(sent.maxOutputTokens == expected.maxOutputTokens)
        #expect(sent.serverSideFallback == expected.serverSideFallback)
        #expect(sent.turns.count == 1)
        #expect(draft(in: sent) == job.fixture.draft)
        guard case .user(let run) = sent.turns[0] else { return }
        #expect(run.contains("<draft id=\"\(record.draftID)\">"))
        #expect(provider.keys == ["test-key"])
    }
}
