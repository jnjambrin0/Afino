import Foundation

/// What to send to the engine: plain strings and turns, which the provider layer turns into an
/// API request.
public struct ComposedPrompt: Sendable, Hashable {
    /// `[CORE, PACK]` or `[CORE, PACK, PREFS]`. Byte-identical for the same target and preferences,
    /// whatever the draft or the conversation, so providers can cache them as a prefix. The blocks
    /// carry no separators of their own; a provider that needs a single string joins them with a
    /// blank line.
    public let systemBlocks: [String]
    /// RUN, then `assistant`/`user` pairs. Never empty; the last turn is always `.user`.
    public let turns: [PromptTurn]

    public init(systemBlocks: [String], turns: [PromptTurn]) {
        self.systemBlocks = systemBlocks
        self.turns = turns
    }
}

/// The single assembler of everything the engine receives.
///
/// The stable, cacheable part goes first and the volatile part last:
/// 1. CORE: `core.txt`, verbatim.
/// 2. PACK: `<target_guidance>` for the chosen target.
/// 3. PREFS: `<user_preferences>`, only when there is something to say.
/// 4. Turns: the RUN message (`<draft id="…">`) and any refinements.
///
/// Nothing dynamic (date, app version, run id) ever enters the system blocks.
public struct PromptComposer: Sendable {
    /// The engine system prompt, exactly as stored in `core.txt`.
    public let core: String

    /// A composer with the given system prompt (tests and previews).
    public init(core: String) {
        self.core = core
    }

    /// A composer with the `core.txt` shipped in this module's bundle.
    public static func bundled() throws(PromptResourceError) -> PromptComposer {
        try PromptComposer(resourcesDirectory: PromptResources.bundledDirectory())
    }

    init(resourcesDirectory: URL) throws(PromptResourceError) {
        core = try PromptResources.readText(
            at: resourcesDirectory.appending(path: PromptResources.coreFileName),
            displayPath: PromptResources.coreFileName
        )
    }

    /// CORE, PACK and, when there is something to say, PREFS.
    public func systemBlocks(for target: TargetPack, preferences: PromptPreferences) -> [String] {
        var blocks = [core, PromptSegments.targetGuidance(for: target)]
        if let preferences = PromptSegments.userPreferences(preferences) {
            blocks.append(preferences)
        }
        return blocks
    }

    /// Starts a conversation for a draft with the system random generator.
    public func startConversation(draft: String, target: TargetPack) -> PromptConversation {
        var generator = SystemRandomNumberGenerator()
        return startConversation(draft: draft, target: target, using: &generator)
    }

    /// Starts a conversation for a draft, rendering the RUN message once.
    ///
    /// The draft's line endings are normalised to LF; nothing else about it changes (no trimming,
    /// interior whitespace kept). Its `<draft>` id is 4–6 random lowercase letters and digits,
    /// drawn again until it does not occur in the draft. Validate the draft with `DraftLimits`
    /// first; the composer itself accepts any text.
    public func startConversation(
        draft: String,
        target: TargetPack,
        using generator: inout some RandomNumberGenerator
    ) -> PromptConversation {
        let draft = TextNormalization.normalizingLineEndings(draft)
        let id = DraftID.make(avoiding: draft, using: &generator)
        return PromptConversation(
            draftID: id,
            runMessage: PromptSegments.run(draft: draft, draftID: id, promptLabel: target.promptLabel)
        )
    }

    /// Everything to send for the conversation's next reply.
    ///
    /// Target and preferences may differ from the ones the conversation started with: they only
    /// change the system blocks, while the stored turns are replayed unchanged (the RUN message
    /// keeps naming the original target, so "Rewrite for X" should start a new conversation).
    public func compose(
        _ conversation: PromptConversation,
        target: TargetPack,
        preferences: PromptPreferences
    ) -> ComposedPrompt {
        ComposedPrompt(
            systemBlocks: systemBlocks(for: target, preferences: preferences),
            turns: conversation.turns
        )
    }
}
