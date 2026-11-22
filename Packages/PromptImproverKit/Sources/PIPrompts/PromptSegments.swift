import Foundation

/// The exact text of every segment the composer assembles. Nothing here reads the clock, the app
/// version or any other ambient state: the same inputs always render the same bytes.
enum PromptSegments {
    /// The `<user_preferences>` line for `OutputLanguage.english`.
    static let englishLanguageLine = """
        Write the prompt in English regardless of the draft's language. If the draft is in another \
        language and does not say which language the answer should be in, ask in the prompt for the \
        answer in the draft's language.
        """

    /// PACK: `<target_guidance>` with the target's label, covered models and guidance.
    static func targetGuidance(for pack: TargetPack) -> String {
        let covers = pack.coversModels.hasSuffix(".") ? pack.coversModels : pack.coversModels + "."
        return "<target_guidance>\nTarget: \(pack.promptLabel) — \(covers)\n\n\(pack.guidance)\n</target_guidance>"
    }

    /// PREFS: `<user_preferences>`, or nil when there is nothing to say (no custom instructions and
    /// the language follows the draft).
    static func userPreferences(_ preferences: PromptPreferences) -> String? {
        var lines: [String] = []
        if preferences.language == .english {
            lines.append(englishLanguageLine)
        }
        if let instructions = preferences.effectiveCustomInstructions {
            lines.append(instructions)
        }
        guard !lines.isEmpty else { return nil }
        return "<user_preferences>\n\(lines.joined(separator: "\n"))\n</user_preferences>"
    }

    /// RUN: the first user message. `draft` must already have LF line endings.
    static func run(draft: String, draftID: String, promptLabel: String) -> String {
        """
        <draft id="\(draftID)">
        \(draft)
        </draft id="\(draftID)">

        Rewrite this draft as a prompt for \(promptLabel). Reply with the prompt only.
        """
    }

    /// REFINE: each later user message. `instruction` must already be normalised.
    static func revision(instruction: String) -> String {
        """
        <revision_request>
        \(instruction)
        </revision_request>

        Apply this to your previous prompt and reply with the complete revised prompt only.
        """
    }
}
