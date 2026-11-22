import Foundation
import PIFoundation

/// Which language the improved prompt is written in.
public enum OutputLanguage: String, Codable, Sendable, CaseIterable, ConfigValue {
    /// The draft's own language (the engine's default behaviour; adds nothing to the system prompt).
    case matchDraft
    /// Always English, asking for the answer in the draft's language when the draft does not say.
    case english
}

/// The person's standing preferences, rendered into `<user_preferences>`.
public struct PromptPreferences: Codable, Sendable, Hashable {
    /// Characters (grapheme clusters) of custom instructions that reach the engine.
    public static let customInstructionsLimit = 2_000

    /// Free text from Settings › Instructions, sent as written (see `effectiveCustomInstructions`).
    public var customInstructions: String
    /// The Instructions switch. Off keeps the text but stops sending it.
    public var customInstructionsEnabled: Bool
    /// The language the improved prompt is written in.
    public var language: OutputLanguage

    public init(
        customInstructions: String = "",
        customInstructionsEnabled: Bool = true,
        language: OutputLanguage = .matchDraft
    ) {
        self.customInstructions = customInstructions
        self.customInstructionsEnabled = customInstructionsEnabled
        self.language = language
    }

    /// The instructions as they are sent: nil when switched off or blank; otherwise line endings
    /// normalised to LF, outer whitespace trimmed, and capped at `customInstructionsLimit`
    /// characters without splitting a character. The interior is left exactly as written.
    public var effectiveCustomInstructions: String? {
        guard customInstructionsEnabled else { return nil }
        let text = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(customInstructions))
        guard !text.isEmpty else { return nil }
        guard text.count > Self.customInstructionsLimit else { return text }
        return TextNormalization.trimmed(text.prefix(Self.customInstructionsLimit))
    }
}
