import Foundation
import PIPrompts
import PIProviders
import Testing
@testable import PICore

@MainActor
struct ImproveSessionTests {
    @Test
    func aRunStreamsCopiesOnceAndIsRecorded() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("escribe un correo a mi casero")
        #expect(session.canSubmit)
        session.submit()
        #expect(session.state.phase == .running(.connecting))

        let request = try #require(fixture.provider.requests.first)
        #expect(request.model == "claude-sonnet-5-5")
        #expect(request.effort == .low)
        #expect(request.serverSideFallback)
        #expect(request.systemBlocks.count == 2)
        #expect(request.systemBlocks[1].contains("<target_guidance>"))
        #expect(request.turns.count == 1)
        #expect(request.maxOutputTokens == 16_000)

        fixture.provider.send(.started(servedModel: "claude-sonnet-5-5", requestID: "req_1"), .textDelta("Redacta "), .textDelta("un correo."), toRun: 0)
        await fixture.settle()
        #expect(session.state.displayedText == "Redacta un correo.")
        #expect(fixture.clipboard.writes.isEmpty)

        fixture.provider.send(.finished(.complete, usage: nil), toRun: 0)
        fixture.provider.finish(run: 0)
        await fixture.settle()
        #expect(session.state.phase == .result)
        #expect(fixture.clipboard.writes == ["Redacta un correo."])

        await fixture.settle()
        let recorded = await fixture.history.all()
        #expect(recorded.map(\.draft) == ["escribe un correo a mi casero"])
        #expect(recorded.first?.latestText == "Redacta un correo.")
        #expect(recorded.first?.targetID == "claude")
    }

    /// Stop followed at once by Improve: the stopped run's late events, completion and error must
    /// not reach the new run, and Stop must still work on the new one.
    @Test
    func stopThenImproveNeverLeaksTheOldRunIntoTheNewOne() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("first draft")
        session.submit()
        fixture.provider.send(.textDelta("Old run text"), toRun: 0)
        await fixture.settle()

        session.stop()
        #expect(session.state.phase == .stopped)
        session.editOriginal()
        session.setDraft("second draft")
        session.submit()
        #expect(session.state.phase == .running(.connecting))

        // Everything the first run still had to say arrives now.
        fixture.provider.send(.textDelta(" …more old text"), .finished(.complete, usage: nil), toRun: 0)
        fixture.provider.finish(run: 0, throwing: EngineFailure(.overloaded))
        await fixture.settle()
        #expect(session.state.phase == .running(.connecting))
        #expect(session.state.displayedText.isEmpty)
        #expect(fixture.clipboard.writes.isEmpty)

        fixture.provider.send(.textDelta("New run text"), toRun: 1)
        await fixture.settle()
        #expect(session.state.displayedText == "New run text")

        // Stop still stops the run that is actually in flight.
        session.stop()
        #expect(session.state.phase == .stopped)
        fixture.provider.send(.textDelta(" ghost"), .finished(.complete, usage: nil), toRun: 1)
        await fixture.settle()
        #expect(session.state.displayedText == "New run text")
        #expect(fixture.clipboard.writes.isEmpty)
        #expect(session.state.versions.isEmpty)
    }

    @Test
    func refineSendsThePreviousOutputAndRegenerateRepeatsTheRequest() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("explain kubernetes")
        session.submit()
        fixture.provider.send(.textDelta("Version one"), .finished(.complete, usage: nil), toRun: 0)
        await fixture.settle()

        session.refine("  shorter ")
        #expect(session.state.pendingInstruction == "shorter")
        let refineRequest = fixture.provider.requests[1]
        #expect(refineRequest.turns.count == 3)
        #expect(refineRequest.turns[0] == fixture.provider.requests[0].turns[0])
        #expect(refineRequest.turns[1] == .assistant("Version one"))
        if case .user(let text) = refineRequest.turns[2] {
            #expect(text.contains("<revision_request>\nshorter\n</revision_request>"))
        } else {
            Issue.record("The last turn must be the revision request")
        }
        fixture.provider.send(.textDelta("V2"), .finished(.complete, usage: nil), toRun: 1)
        await fixture.settle()
        #expect(session.state.versions.map(\.text) == ["Version one", "V2"])
        #expect(fixture.clipboard.writes == ["Version one", "V2"])

        session.regenerate()
        #expect(fixture.provider.requests[2].turns == refineRequest.turns)
        fixture.provider.send(.textDelta("V2 again"), .finished(.complete, usage: nil), toRun: 2)
        await fixture.settle()
        #expect(session.state.versions.count == 3)

        // Stepping back to the first version and refining extends that version's conversation.
        session.selectVersion(0)
        #expect(fixture.clipboard.writes.last == "Version one")
        session.refine("add an example")
        #expect(fixture.provider.requests[3].turns.count == 3)
        #expect(fixture.provider.requests[3].turns[1] == .assistant("Version one"))

        await fixture.settle()
        let entries = await fixture.history.all()
        #expect(entries.count == 1)
        #expect(entries.first?.versions.count == 3)
    }

    @Test
    func tryAgainResendsTheSameRequestAfterAFailure() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("draft")
        session.submit()
        fixture.provider.finish(run: 0, throwing: EngineFailure(.overloaded, provider: .anthropic, requestID: "req_7"))
        await fixture.settle()
        #expect(session.state.phase == .failed(.engine(.overloaded, provider: .anthropic, requestID: "req_7")))
        #expect(session.state.origin == "draft")

        session.retry()
        #expect(session.state.isRunning)
        #expect(fixture.provider.requests[1].turns == fixture.provider.requests[0].turns)
    }

    @Test
    func aMissingKeyFailsWithoutCallingTheProvider() async throws {
        let fixture = try SessionFixture(storedKey: nil)
        #expect(!fixture.session.hasUsableKey)
        fixture.session.setDraft("draft")
        fixture.session.submit()
        #expect(fixture.session.state.phase == .failed(.engine(.missingKey(.anthropic), provider: .anthropic, requestID: nil)))
        #expect(fixture.provider.requests.isEmpty)
    }

    @Test
    func aRejectedKeyIsMarkedInTheVault() async throws {
        let fixture = try SessionFixture()
        fixture.session.setDraft("draft")
        fixture.session.submit()
        fixture.provider.finish(run: 0, throwing: EngineFailure(.invalidKey(.anthropic), provider: .anthropic))
        await fixture.settle()
        #expect(fixture.vault.state(for: .anthropic) == .invalid(masked: APIKey("sk-ant-test-key-1234").masked))
        #expect(!fixture.session.hasUsableKey)
    }

    @Test
    func theRunCarriesOnWhenThePanelCloses() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("draft")
        session.submit()
        session.panelDidClose()
        #expect(session.state.isRunning)
        fixture.provider.send(.textDelta("Done"), .finished(.complete, usage: nil), toRun: 0)
        await fixture.settle()
        #expect(fixture.clipboard.writes == ["Done"])
        session.panelDidClose()
        #expect(session.state.phase == .composing)
        #expect(session.state.draft.isEmpty)
    }

    @Test
    func changingTargetCyclesPersistsAndOffersARewrite() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        #expect(session.state.targetID == "claude")
        session.cycleTarget(forward: true)
        #expect(session.state.targetID == "gpt")
        #expect(fixture.settings.lastTargetID == "gpt")
        session.cycleTarget(forward: false)
        session.cycleTarget(forward: false)
        #expect(session.state.targetID == "generic")
        session.setTarget("claude")

        session.setDraft("draft")
        session.submit()
        #expect(fixture.provider.requests[0].systemBlocks[1].contains("Claude (Anthropic)"))
        fixture.provider.send(.textDelta("For Claude"), .finished(.complete, usage: nil), toRun: 0)
        await fixture.settle()

        session.setTarget("gemini")
        #expect(session.state.needsRewriteForTarget)
        session.rewriteForTarget()
        let rewrite = fixture.provider.requests[1]
        #expect(rewrite.systemBlocks[1].contains("Gemini (Google)"))
        #expect(rewrite.turns.count == 1)
    }

    @Test
    func customInstructionsAndLanguageReachTheRequest() async throws {
        let fixture = try SessionFixture()
        fixture.settings.customInstructions = "Prefer XML tags."
        fixture.settings.outputLanguage = .english
        fixture.session.setDraft("borrador")
        fixture.session.submit()
        let blocks = fixture.provider.requests[0].systemBlocks
        #expect(blocks.count == 3)
        #expect(blocks[2].contains("Prefer XML tags."))
        #expect(blocks[2].contains("Write the prompt in English"))
    }

    @Test
    func historyOffRecordsNothing() async throws {
        let fixture = try SessionFixture(historyEnabled: false)
        fixture.session.setDraft("private draft")
        fixture.session.submit()
        fixture.provider.send(.textDelta("Result"), .finished(.complete, usage: nil), toRun: 0)
        await fixture.settle()
        await fixture.settle()
        #expect(!FileManager.default.fileExists(atPath: fixture.historyFile.path(percentEncoded: false)))
    }

    @Test
    func upArrowRecallsEarlierDrafts() async throws {
        let fixture = try SessionFixture()
        await fixture.history.load()
        let session = fixture.session
        for (index, draft) in ["older draft", "newer draft"].enumerated() {
            session.setDraft(draft)
            session.submit()
            fixture.provider.send(.textDelta("R"), .finished(.complete, usage: nil), toRun: index)
            await fixture.settle()
            session.newPrompt()
        }
        await session.refreshRecallDrafts()

        #expect(session.recallDraft(older: true))
        #expect(session.state.draft == "newer draft")
        #expect(session.recallDraft(older: true))
        #expect(session.state.draft == "older draft")
        #expect(session.recallDraft(older: false))
        #expect(session.state.draft == "newer draft")
        #expect(session.recallDraft(older: false))
        #expect(session.state.draft.isEmpty)

        // Once the user types, the arrows belong to the text again.
        session.setDraft("typing")
        #expect(!session.recallDraft(older: true))
    }

    @Test
    func openingAHistoryEntryShowsItReadyToRefine() async throws {
        let fixture = try SessionFixture()
        let entry = HistoryEntry(
            draft: "old draft", targetID: "gpt",
            versions: [.init(text: "First"), .init(text: "Second", instruction: "shorter")],
            provider: "openai", model: "gpt-6.2-sol")
        fixture.session.open(entry)
        #expect(fixture.session.state.phase == .result)
        #expect(fixture.session.state.displayedText == "Second")
        #expect(fixture.session.state.targetID == "gpt")
        #expect(fixture.clipboard.writes == ["Second"])

        fixture.session.refine("more formal")
        let turns = fixture.provider.requests[0].turns
        #expect(turns.count == 5)
        #expect(turns[1] == .assistant("First"))
        #expect(turns[3] == .assistant("Second"))
    }
}

extension ImproveSessionTests {
    /// A result rewritten for another target keeps its own target in the history, so reopening
    /// the entry and refining either version talks to the right pack.
    @Test
    func historyRemembersTheTargetOfEachVersion() async throws {
        let fixture = try SessionFixture()
        let session = fixture.session
        session.setDraft("draft")
        session.submit()
        fixture.provider.send(.textDelta("For Claude"), .finished(.complete, usage: nil), toRun: 0)
        await fixture.settle()
        session.setTarget("gemini")
        session.rewriteForTarget()
        fixture.provider.send(.textDelta("For Gemini"), .finished(.complete, usage: nil), toRun: 1)
        await fixture.settle()
        await fixture.settle()

        let entry = try #require(await fixture.history.all().first)
        #expect(entry.targetID == "claude")
        #expect(entry.versions.map(\.targetID) == [nil, "gemini"])

        session.newPrompt()
        session.open(entry)
        #expect(session.state.targetID == "gemini")
        session.selectVersion(0)
        session.setTarget("claude")
        session.refine("shorter")
        let request = try #require(fixture.provider.requests.last)
        #expect(request.systemBlocks[1].contains("Claude (Anthropic)"))
        #expect(request.turns[1] == .assistant("For Claude"))
    }
}
