import Foundation
import PIProviders

/// One complete prompt the engine wrote during a session.
public nonisolated struct PromptVersion: Sendable, Equatable, Identifiable {
    /// Distinguishes versions with the same text.
    public let id: UUID
    /// The finished text, as shown and copied.
    public var text: String
    /// The refine instruction that led to it; `nil` for a first result, a regeneration or a rewrite
    /// for another target.
    public var instruction: String?
    /// The target pack it was written for.
    public var targetID: String
    /// The model that actually served it (a server-side fallback can differ from the one asked for).
    public var model: String

    public init(id: UUID = UUID(), text: String, instruction: String? = nil, targetID: String, model: String) {
        self.id = id
        self.text = text
        self.instruction = instruction
        self.targetID = targetID
        self.model = model
    }
}

/// Why a run did not end in a usable prompt.
public nonisolated enum SessionProblem: Sendable, Equatable {
    /// The request failed. `requestID` is the provider's identifier, for "Copy details".
    case engine(EngineError, provider: ProviderID?, requestID: String?)
    /// Cut off at the output limit; the partial text is kept but was not copied.
    case truncated
    /// The model declined; nothing is kept.
    case refused(category: String?)
    /// The model answered with nothing.
    case emptyOutput
}

/// Everything the panel shows. A value type changed only by `RunReducer`, so every transition can
/// be tested without a window, a network or a clock.
public nonisolated struct SessionState: Sendable, Equatable {
    /// Where the session is, and so which screen the panel shows.
    public enum Phase: Sendable, Equatable {
        /// Writing the draft.
        case composing
        /// A run is in flight.
        case running(RunStage)
        /// A complete version is shown (and is on the clipboard).
        case result
        /// The run ended without a usable prompt; any partial text is in `liveText`.
        case failed(SessionProblem)
        /// The user stopped a run that had already written something; the partial text is kept.
        case stopped
    }

    /// What a run in flight is doing, for the status line.
    public enum RunStage: Sendable, Equatable {
        /// Sent, nothing back yet.
        case connecting
        /// The model is thinking before it writes.
        case thinking
        /// Text is arriving.
        case writing
        /// Waiting to send the request again.
        case retrying(RetryReason)
    }

    /// Where the session is.
    public var phase: Phase = .composing
    /// The text in the compose input.
    public var draft: String = ""
    /// The draft this session's versions were written from; `nil` while composing a fresh one.
    public var origin: String?
    /// The chosen target pack.
    public var targetID: String
    /// Every complete version of this session, oldest first.
    public var versions: [PromptVersion] = []
    /// Index into `versions` of the one on screen.
    public var shownVersion: Int = 0
    /// What a run has written so far, already in display form. After a failure or a stop it holds
    /// the partial text.
    public var liveText: String = ""
    /// The refine instruction of the run in flight.
    public var pendingInstruction: String?
    /// When the latest run was sent, for its elapsed time.
    public var runStartedAt: Date?
    /// When the latest run ended, by finishing, failing or being stopped.
    public var runEndedAt: Date?
    /// The model the provider named as answering the latest run.
    public var servedModel: String?
    /// Whether the clipboard holds exactly what is on screen.
    public var isCopied: Bool = false
    /// Identifies the current run. Anything that arrives for another run is ignored.
    public var runID: Int = 0

    /// Text as the engine sent it, before display rules. Not for the interface.
    var rawText: String = ""

    public init(targetID: String, draft: String = "") {
        self.targetID = targetID
        self.draft = draft
    }

    /// Whether a run is in flight.
    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// The version on screen, if there is one.
    public var shown: PromptVersion? {
        versions.indices.contains(shownVersion) ? versions[shownVersion] : nil
    }

    /// The text in the result well for the current phase.
    public var displayedText: String {
        switch phase {
        case .composing: ""
        case .running, .failed, .stopped: liveText
        case .result: shown?.text ?? ""
        }
    }

    /// Whether the user picked another target after the shown version was written, so Return
    /// should offer "Rewrite for …".
    public var needsRewriteForTarget: Bool {
        guard phase == .result, let shown else { return false }
        return shown.targetID != targetID
    }
}
