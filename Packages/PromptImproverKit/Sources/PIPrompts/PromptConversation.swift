import Foundation

/// One message of the conversation sent to the engine. Assistant turns are plain text only: no
/// thinking or reasoning blocks are ever replayed, so target, engine and preferences can change
/// between turns.
public enum PromptTurn: Sendable, Hashable {
    /// A RUN or REFINE message.
    case user(String)
    /// An output the person was shown.
    case assistant(String)

    /// Who a turn is from, without its text.
    public enum Role: String, Sendable, Hashable {
        case user
        case assistant
    }

    /// Who the turn is from.
    public var role: Role {
        switch self {
        case .user: .user
        case .assistant: .assistant
        }
    }

    /// The turn's text, exactly as it is sent.
    public var text: String {
        switch self {
        case .user(let text), .assistant(let text): text
        }
    }
}

/// A run and its refinements, as a value.
///
/// Start one with `PromptComposer.startConversation(draft:target:)`. The first user message (RUN)
/// is rendered once and stored, so every replay sends byte-identical text. Each refinement appends
/// the output the person was shown and a `<revision_request>` user message. Pass the conversation
/// to `PromptComposer.compose(_:target:preferences:)` to get what to send.
public struct PromptConversation: Sendable, Hashable {
    /// A shown output and the revision request that followed it.
    public struct Revision: Sendable, Hashable {
        /// The assistant turn: the text the person was shown, exactly.
        public let previousOutput: String
        /// The rendered REFINE user message.
        public let requestMessage: String
    }

    /// Revisions kept in the conversation. Past this, the oldest are dropped; the RUN message and
    /// the latest output are always kept.
    public static let maxRevisionTurns = 12

    /// The id in the RUN message's `<draft>` tags.
    public let draftID: String
    /// The rendered RUN message.
    public let runMessage: String
    /// The kept revisions, oldest first; at most `maxRevisionTurns`.
    public private(set) var revisions: [Revision] = []
    /// Revisions ever appended, including dropped ones.
    public private(set) var revisionCount = 0

    init(draftID: String, runMessage: String) {
        self.draftID = draftID
        self.runMessage = runMessage
    }

    /// RUN, then an `assistant`/`user` pair per kept revision. Always starts and ends with a user turn.
    public var turns: [PromptTurn] {
        var turns: [PromptTurn] = [.user(runMessage)]
        turns.reserveCapacity(1 + revisions.count * 2)
        for revision in revisions {
            turns.append(.assistant(revision.previousOutput))
            turns.append(.user(revision.requestMessage))
        }
        return turns
    }

    /// Revisions dropped by the cap.
    public var droppedRevisionCount: Int {
        revisionCount - revisions.count
    }

    /// Adds a refinement.
    ///
    /// - Parameters:
    ///   - previousOutput: The output the person was shown (already post-processed), sent back
    ///     verbatim as the assistant turn. Callers only refine a non-empty result.
    ///   - instruction: What to change ("shorter"). Line endings are normalised and outer
    ///     whitespace trimmed; the rest is sent as typed.
    public mutating func appendRevision(previousOutput: String, instruction: String) {
        let instruction = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(instruction))
        revisions.append(Revision(
            previousOutput: previousOutput,
            requestMessage: PromptSegments.revision(instruction: instruction)
        ))
        revisionCount += 1
        if revisions.count > Self.maxRevisionTurns {
            revisions.removeFirst(revisions.count - Self.maxRevisionTurns)
        }
    }

    /// Non-mutating `appendRevision(previousOutput:instruction:)`.
    public func appendingRevision(previousOutput: String, instruction: String) -> PromptConversation {
        var copy = self
        copy.appendRevision(previousOutput: previousOutput, instruction: instruction)
        return copy
    }
}
