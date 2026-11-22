import Foundation
import PIPrompts
import PIProviders

/// What starts a run.
public nonisolated enum RunKind: Sendable, Equatable {
    /// The draft, sent for the first time.
    case first
    /// The shown version, revised as `instruction` asks.
    case refine(instruction: String)
    /// The request behind the shown version, sent again for a new version.
    case regenerate
    /// The same draft rewritten for the target chosen after the result.
    case rewriteForTarget
}

/// Everything that can change a `SessionState`.
public nonisolated enum SessionAction: Sendable, Equatable {
    /// The compose input changed.
    case setDraft(String)
    /// Another target was picked.
    case setTarget(String)
    /// A run was sent. `draft` is the text it rewrites.
    case began(runID: Int, kind: RunKind, draft: String, at: Date)
    /// The provider reported something for the run.
    case event(runID: Int, EngineEvent, at: Date)
    /// The provider's stream ended. Without a `.finished` event before it, the answer was cut short.
    case streamEnded(runID: Int, at: Date)
    /// The run's stream threw.
    case failed(runID: Int, EngineFailure, at: Date)
    /// The user stopped the run in flight.
    case stop(at: Date)
    /// Back to the composer with the draft the versions were written from.
    case editOriginal
    /// Back to an empty composer.
    case newPrompt
    /// The panel was dismissed.
    case panelClosed
    /// Shows (and copies) another version.
    case selectVersion(Int)
    /// ⌘C with nothing selected.
    case copyShown
    /// A past improvement opened from the history.
    case restore(draft: String, targetID: String, versions: [PromptVersion])
}

/// What the reducer asks the outside world to do. The reducer itself touches nothing.
public nonisolated enum SessionEffect: Sendable, Equatable {
    /// Put this text on the clipboard.
    case copy(String)
    /// Save the session's versions to the history.
    case recordHistory
    /// The provider refused the key during a run; mark it invalid.
    case keyRejected(ProviderID)
}

/// The session's only source of state changes.
///
/// Every action that belongs to a run carries that run's id, and anything for a run that is no
/// longer current is dropped. That is what makes Stop followed at once by Improve safe: the old
/// run's late events, its completion and its errors cannot cancel, fail or fill the new run.
public nonisolated enum RunReducer {
    /// Applies `action` to `state` and returns what must happen outside it.
    public static func reduce(_ state: inout SessionState, _ action: SessionAction) -> [SessionEffect] {
        switch action {
        case .setDraft(let draft):
            state.draft = draft
            return []

        case .setTarget(let id):
            state.targetID = id
            return []

        case .began(let runID, let kind, let draft, let date):
            state.runID = runID
            state.phase = .running(.connecting)
            state.origin = draft
            state.rawText = ""
            state.liveText = ""
            state.isCopied = false
            state.runStartedAt = date
            state.runEndedAt = nil
            state.servedModel = nil
            if case .refine(let instruction) = kind {
                state.pendingInstruction = instruction
            } else {
                state.pendingInstruction = nil
            }
            return []

        case .event(let runID, let event, let date):
            guard runID == state.runID, state.isRunning else { return [] }
            return apply(event, to: &state, at: date)

        case .streamEnded(let runID, let date):
            guard runID == state.runID, state.isRunning else { return [] }
            let problem = SessionProblem.engine(
                .connectionLost(receivedText: !state.rawText.isEmpty), provider: nil, requestID: nil)
            fail(&state, with: problem, at: date)
            return []

        case .failed(let runID, let failure, let date):
            guard runID == state.runID, state.isRunning else { return [] }
            if failure.error == .cancelled { return [] }
            fail(
                &state,
                with: .engine(failure.error, provider: failure.provider, requestID: failure.requestID),
                at: date)
            if case .invalidKey(let provider) = failure.error {
                return [.keyRejected(provider)]
            }
            return []

        case .stop(let date):
            guard state.isRunning else { return [] }
            // Whatever the stopped run still sends is for a run that no longer exists.
            state.runID &+= 1
            state.runEndedAt = date
            state.pendingInstruction = nil
            if state.rawText.isEmpty {
                if state.versions.isEmpty {
                    state.draft = state.origin ?? state.draft
                    state.origin = nil
                    state.phase = .composing
                } else {
                    state.phase = .result
                }
                return []
            }
            state.liveText = finalText(of: state)
            state.phase = .stopped
            return []

        case .editOriginal:
            guard !state.isRunning, let origin = state.origin else { return [] }
            resetSession(&state, draft: origin)
            return []

        case .newPrompt:
            guard !state.isRunning else { return [] }
            resetSession(&state, draft: "")
            return []

        case .panelClosed:
            switch state.phase {
            case .composing, .running:
                return []
            case .result:
                resetSession(&state, draft: "")
            case .failed, .stopped:
                resetSession(&state, draft: state.origin ?? "")
            }
            return []

        case .selectVersion(let index):
            guard state.phase == .result, state.versions.indices.contains(index), index != state.shownVersion else { return [] }
            state.shownVersion = index
            state.isCopied = true
            return [.copy(state.versions[index].text)]

        case .copyShown:
            let text = state.displayedText
            guard !text.isEmpty else { return [] }
            state.isCopied = true
            return [.copy(text)]

        case .restore(let draft, let targetID, let versions):
            guard !state.isRunning, let last = versions.last else { return [] }
            resetSession(&state, draft: "")
            state.origin = draft
            state.targetID = targetID
            state.versions = versions
            state.shownVersion = versions.count - 1
            state.phase = .result
            state.isCopied = true
            return [.copy(last.text)]
        }
    }

    private static func apply(_ event: EngineEvent, to state: inout SessionState, at date: Date) -> [SessionEffect] {
        switch event {
        case .retrying(_, _, let reason):
            state.phase = .running(.retrying(reason))
            return []

        case .started(let model, _):
            state.servedModel = model
            if state.rawText.isEmpty {
                state.phase = .running(.connecting)
            }
            return []

        case .thinking:
            if state.rawText.isEmpty {
                state.phase = .running(.thinking)
            }
            return []

        case .textDelta(let delta):
            state.rawText += delta
            state.liveText = OutputPostProcessor.StreamingDisplay(draft: state.origin ?? "").text(for: state.rawText)
            state.phase = .running(.writing)
            return []

        case .finished(.complete, _):
            let text = finalText(of: state)
            guard !text.isEmpty else {
                fail(&state, with: .emptyOutput, at: date)
                return []
            }
            let version = PromptVersion(
                text: text,
                instruction: state.pendingInstruction,
                targetID: state.targetID,
                model: state.servedModel ?? "")
            state.versions.append(version)
            state.shownVersion = state.versions.count - 1
            state.liveText = ""
            state.rawText = ""
            state.pendingInstruction = nil
            state.runEndedAt = date
            state.phase = .result
            state.isCopied = true
            return [.copy(text), .recordHistory]

        case .finished(.truncated, _):
            fail(&state, with: .truncated, at: date)
            return []

        case .finished(.refused(let category), _):
            // A declined request can stop mid-sentence: nothing of it is worth keeping.
            state.rawText = ""
            fail(&state, with: .refused(category: category), at: date)
            return []
        }
    }

    /// Ends the run as `problem`, keeping whatever text it had written.
    private static func fail(_ state: inout SessionState, with problem: SessionProblem, at date: Date) {
        state.liveText = finalText(of: state)
        state.runEndedAt = date
        state.pendingInstruction = nil
        state.isCopied = false
        state.phase = .failed(problem)
    }

    /// The run's text with the completion rules applied (outer whitespace, one wrapping fence).
    private static func finalText(of state: SessionState) -> String {
        OutputPostProcessor.finalize(state.rawText, draft: state.origin ?? "")
    }

    /// Clears every trace of the session's runs and puts `draft` in the composer.
    private static func resetSession(_ state: inout SessionState, draft: String) {
        state.phase = .composing
        state.draft = draft
        state.origin = nil
        state.versions = []
        state.shownVersion = 0
        state.liveText = ""
        state.rawText = ""
        state.pendingInstruction = nil
        state.runStartedAt = nil
        state.runEndedAt = nil
        state.servedModel = nil
        state.isCopied = false
    }
}
