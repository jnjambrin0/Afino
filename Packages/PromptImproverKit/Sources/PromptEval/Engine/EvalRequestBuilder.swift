import Foundation
import PIPrompts
import PIProviders

/// Builds engine requests exactly as the app does.
///
/// Mirrors the private `ImproveSession.start(_:kind:draft:)` in PICore, which this target
/// cannot import: compose the conversation for the target and preferences, size the output budget
/// from the characters of the turns, and map the turns one to one. No test compares the two, so
/// a change to that method needs the same change here.
enum EvalRequestBuilder {
    /// The request the app would send for `conversation`.
    static func request(
        for conversation: PromptConversation,
        target: TargetPack,
        preferences: PromptPreferences,
        selection: EngineSelection,
        composer: PromptComposer
    ) -> EngineRequest {
        let prompt = composer.compose(conversation, target: target, preferences: preferences)
        let inputCharacters = prompt.turns.reduce(0) { $0 + $1.text.count }
        return EngineRequest(
            selection: selection,
            maxOutputTokens: ModelCatalog.maxOutputTokens(forInputCharacters: inputCharacters, capabilities: selection.capabilities),
            systemBlocks: prompt.systemBlocks,
            turns: prompt.turns.map { turn in
                switch turn {
                case .user(let text): .user(text)
                case .assistant(let text): .assistant(text)
                }
            }
        )
    }
}
