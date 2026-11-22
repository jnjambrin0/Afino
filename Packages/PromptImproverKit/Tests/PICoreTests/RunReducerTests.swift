import Foundation
import PIProviders
import Testing
@testable import PICore

struct RunReducerTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func running(_ draft: String = "write a haiku", runID: Int = 1) -> SessionState {
        var state = SessionState(targetID: "claude", draft: draft)
        _ = RunReducer.reduce(&state, .began(runID: runID, kind: .first, draft: draft, at: date))
        return state
    }

    private func event(_ event: EngineEvent, runID: Int = 1) -> SessionAction {
        .event(runID: runID, event, at: date)
    }

    @Test
    func aRunMovesThroughConnectingThinkingWritingToResult() {
        var state = running()
        #expect(state.phase == .running(.connecting))
        #expect(state.origin == "write a haiku")

        _ = RunReducer.reduce(&state, event(.started(servedModel: "claude-sonnet-5-5", requestID: "req_1")))
        _ = RunReducer.reduce(&state, event(.thinking))
        #expect(state.phase == .running(.thinking))

        _ = RunReducer.reduce(&state, event(.textDelta("Write a haiku ")))
        _ = RunReducer.reduce(&state, event(.textDelta("about autumn rain.\n")))
        #expect(state.phase == .running(.writing))
        #expect(state.displayedText == "Write a haiku about autumn rain.\n")

        // Thinking after text has started does not send the status back.
        _ = RunReducer.reduce(&state, event(.thinking))
        #expect(state.phase == .running(.writing))

        let effects = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        #expect(state.phase == .result)
        #expect(state.versions.map(\.text) == ["Write a haiku about autumn rain."])
        #expect(state.shown?.model == "claude-sonnet-5-5")
        #expect(state.isCopied)
        #expect(effects == [.copy("Write a haiku about autumn rain."), .recordHistory])
    }

    @Test
    func eventsOfAnotherRunAreIgnored() {
        var state = running(runID: 2)
        let before = state
        #expect(RunReducer.reduce(&state, event(.textDelta("late text"), runID: 1)).isEmpty)
        #expect(RunReducer.reduce(&state, event(.finished(.complete, usage: nil), runID: 1)).isEmpty)
        #expect(RunReducer.reduce(&state, .streamEnded(runID: 1, at: date)).isEmpty)
        #expect(RunReducer.reduce(&state, .failed(runID: 1, EngineFailure(.overloaded), at: date)).isEmpty)
        #expect(state == before)
    }

    @Test
    func stopBeforeAnyTextReturnsToTheDraft() {
        var state = running("my draft")
        #expect(RunReducer.reduce(&state, .stop(at: date)).isEmpty)
        #expect(state.phase == .composing)
        #expect(state.draft == "my draft")
        #expect(state.origin == nil)
        // What the stopped run still sends is for a run that no longer exists.
        #expect(RunReducer.reduce(&state, event(.textDelta("ghost"))).isEmpty)
        #expect(state.displayedText.isEmpty)
    }

    @Test
    func stopWithPartialTextKeepsItUncopied() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("Half a pro")))
        let effects = RunReducer.reduce(&state, .stop(at: date))
        #expect(state.phase == .stopped)
        #expect(state.displayedText == "Half a pro")
        #expect(!state.isCopied)
        #expect(effects.isEmpty)
        #expect(state.versions.isEmpty)
    }

    @Test
    func truncatedKeepsThePartialTextAndCopiesNothing() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("A long prompt that was cut")))
        let effects = RunReducer.reduce(&state, event(.finished(.truncated, usage: nil)))
        #expect(state.phase == .failed(.truncated))
        #expect(state.displayedText == "A long prompt that was cut")
        #expect(effects.isEmpty)
        #expect(state.versions.isEmpty)
    }

    @Test
    func refusalDiscardsWhatWasWritten() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("I can")))
        let effects = RunReducer.reduce(&state, event(.finished(.refused(category: "cyber"), usage: nil)))
        #expect(state.phase == .failed(.refused(category: "cyber")))
        #expect(state.displayedText.isEmpty)
        #expect(effects.isEmpty)
    }

    @Test
    func emptyOutputIsAProblemNotAVersion() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("  \n")))
        let effects = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        #expect(state.phase == .failed(.emptyOutput))
        #expect(effects.isEmpty)
    }

    @Test
    func aStreamThatEndsWithoutFinishingIsALostConnection() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("Partial")))
        _ = RunReducer.reduce(&state, .streamEnded(runID: 1, at: date))
        #expect(state.phase == .failed(.engine(.connectionLost(receivedText: true), provider: nil, requestID: nil)))
        #expect(state.displayedText == "Partial")
    }

    @Test
    func aRejectedKeyIsReportedForTheVault() {
        var state = running()
        let failure = EngineFailure(.invalidKey(.anthropic), provider: .anthropic, requestID: "req_9")
        let effects = RunReducer.reduce(&state, .failed(runID: 1, failure, at: date))
        let problem = SessionProblem.engine(.invalidKey(.anthropic), provider: .anthropic, requestID: "req_9")
        #expect(state.phase == .failed(problem))
        #expect(effects == [.keyRejected(.anthropic)])
    }

    @Test
    func cancellationIsNeverShown() {
        var state = running()
        #expect(RunReducer.reduce(&state, .failed(runID: 1, EngineFailure(.cancelled), at: date)).isEmpty)
        #expect(state.phase == .running(.connecting))
    }

    @Test
    func retryingShowsWhyAndASecondStartKeepsGoing() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.retrying(attempt: 2, after: .seconds(1), reason: .overloaded)))
        #expect(state.phase == .running(.retrying(.overloaded)))
        _ = RunReducer.reduce(&state, event(.started(servedModel: "m", requestID: nil)))
        #expect(state.phase == .running(.connecting))
    }

    @Test
    func aWrappingFenceIsHiddenWhileStreamingAndRemovedAtTheEnd() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("```\nSummarise the text")))
        #expect(state.displayedText == "Summarise the text")
        _ = RunReducer.reduce(&state, event(.textDelta(".\n```")))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        #expect(state.shown?.text == "Summarise the text.")
    }

    @Test
    func refinementAddsAVersionWithItsInstruction() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("First version")))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))

        _ = RunReducer.reduce(&state, .began(runID: 2, kind: .refine(instruction: "shorter"), draft: "write a haiku", at: date))
        #expect(state.pendingInstruction == "shorter")
        #expect(!state.isCopied)
        _ = RunReducer.reduce(&state, event(.textDelta("Second"), runID: 2))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil), runID: 2))
        #expect(state.versions.map(\.text) == ["First version", "Second"])
        #expect(state.versions.map(\.instruction) == [nil, "shorter"])
        #expect(state.shownVersion == 1)

        let effects = RunReducer.reduce(&state, .selectVersion(0))
        #expect(state.shown?.text == "First version")
        #expect(effects == [.copy("First version")])
    }

    @Test
    func stoppingARefinementBeforeTextGoesBackToTheResult() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("First version")))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        _ = RunReducer.reduce(&state, .began(runID: 2, kind: .refine(instruction: "shorter"), draft: "write a haiku", at: date))
        _ = RunReducer.reduce(&state, .stop(at: date))
        #expect(state.phase == .result)
        #expect(state.displayedText == "First version")
    }

    @Test
    func closingThePanelEndsAFinishedSessionButKeepsAFailedDraft() {
        var finished = running()
        _ = RunReducer.reduce(&finished, event(.textDelta("Done")))
        _ = RunReducer.reduce(&finished, event(.finished(.complete, usage: nil)))
        _ = RunReducer.reduce(&finished, .panelClosed)
        #expect(finished.phase == .composing)
        #expect(finished.draft.isEmpty)
        #expect(finished.versions.isEmpty)

        var failed = running("keep me")
        _ = RunReducer.reduce(&failed, .failed(runID: 1, EngineFailure(.offline), at: date))
        _ = RunReducer.reduce(&failed, .panelClosed)
        #expect(failed.phase == .composing)
        #expect(failed.draft == "keep me")

        var inFlight = running()
        let before = inFlight
        _ = RunReducer.reduce(&inFlight, .panelClosed)
        #expect(inFlight == before)
    }

    @Test
    func changingTheTargetAfterAResultOffersARewrite() {
        var state = running()
        _ = RunReducer.reduce(&state, event(.textDelta("For Claude")))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        #expect(!state.needsRewriteForTarget)
        _ = RunReducer.reduce(&state, .setTarget("gpt"))
        #expect(state.needsRewriteForTarget)
    }

    @Test
    func editOriginalReturnsTheDraftToTheComposer() {
        var state = running("original words")
        _ = RunReducer.reduce(&state, event(.textDelta("Improved")))
        _ = RunReducer.reduce(&state, event(.finished(.complete, usage: nil)))
        _ = RunReducer.reduce(&state, .editOriginal)
        #expect(state.phase == .composing)
        #expect(state.draft == "original words")
        #expect(state.versions.isEmpty)
    }
}
