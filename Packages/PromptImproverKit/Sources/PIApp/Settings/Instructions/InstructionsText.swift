import Foundation
import PIPrompts

/// The rules of the custom instructions editor: the 2,000-character cap, the counter and the
/// example chips. Pure, so they can be tested without a text view. Characters are counted as the
/// prompt engine counts them (`String.count`, grapheme clusters).
enum InstructionsText {
    static let limit = PromptPreferences.customInstructionsLimit

    /// The examples offered as chips, in order.
    enum Example: String, CaseIterable, Sendable {
        case alwaysEnglish
        case xmlTags
        case under200Words
        case noRoleLine

        /// The chip title, which is also the sentence it adds.
        var sentence: String {
            switch self {
            case .alwaysEnglish: SettingsStrings.text("settings.instructions.example.english")
            case .xmlTags: SettingsStrings.text("settings.instructions.example.xml")
            case .under200Words: SettingsStrings.text("settings.instructions.example.short")
            case .noRoleLine: SettingsStrings.text("settings.instructions.example.noRole")
            }
        }
    }

    /// The counter's state.
    struct Count: Equatable, Sendable {
        let used: Int
        let limit: Int

        /// From 90 % of the limit (`SettingsLayout.instructionsWarningFraction`) the counter
        /// turns orange.
        var isNearLimit: Bool {
            Double(used) >= Double(limit) * SettingsLayout.instructionsWarningFraction
        }

        /// "212 / 2,000", with the user's digit grouping.
        var text: String {
            SettingsStrings.text("settings.instructions.counter", used.formatted(), limit.formatted())
        }

        var accessibilityText: String {
            SettingsStrings.text("settings.instructions.counter.accessibility", used.formatted(), limit.formatted())
        }
    }

    static func count(of text: String) -> Count {
        Count(used: text.count, limit: limit)
    }

    /// What an edit may insert: all of `replacement` when the result stays within the limit, the
    /// part that fits otherwise (never splitting a character), or nil when nothing fits.
    ///
    /// - Parameters:
    ///   - text: The text before the edit.
    ///   - range: The UTF-16 range the edit replaces.
    static func allowedReplacement(in text: String, range: NSRange, replacement: String) -> String? {
        let current = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= current.length else { return nil }
        let removed = current.substring(with: range).count
        let available = limit - (text.count - removed)
        if replacement.count <= available { return replacement }
        guard available > 0 else { return nil }
        return String(replacement.prefix(available))
    }

    /// `text` with `sentence` added on a line of its own; nil when it would pass the limit or the
    /// line is already there.
    static func appending(_ sentence: String, to text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.contains(sentence) else { return nil }
        let result: String
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = sentence
        } else if text.last?.isNewline == true {
            result = text + sentence
        } else {
            result = text + "\n" + sentence
        }
        return result.count <= limit ? result : nil
    }

    /// `text` cut to the limit. The editor's binding stores everything through it, a last guard
    /// behind the check the editor makes on each edit.
    static func capped(_ text: String) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}
