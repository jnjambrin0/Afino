import Foundation
import NaturalLanguage

/// Pure text measurements used by the checks.
enum TextAnalysis {
    // MARK: - Words

    /// Whitespace-separated tokens that contain at least one letter or digit.
    static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace).filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }
    }

    static func wordCount(_ text: String) -> Int {
        words(text).count
    }

    /// Lowercased runs of letters and digits, for similarity.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Dice coefficient over token multisets: 1 for the same words in any order, 0 for none shared.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = tokens(a)
        let right = tokens(b)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        var counts: [String: Int] = [:]
        for token in left { counts[token, default: 0] += 1 }
        var shared = 0
        for token in right {
            if let count = counts[token], count > 0 {
                shared += 1
                counts[token] = count - 1
            }
        }
        return Double(2 * shared) / Double(left.count + right.count)
    }

    // MARK: - Lines

    static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    static func nonBlankLines(_ text: String) -> [Substring] {
        lines(text).filter { !$0.allSatisfy(\.isWhitespace) }
    }

    /// Lines outside code blocks that start a Markdown list item (`-`, `*`, `•`, `+`, `1.` or `1)`).
    static func listItemCount(_ text: String) -> Int {
        let pattern = #"^\s{0,6}([-*•+]|\d{1,2}[.)])\s+\S"#
        return lines(textWithoutCodeBlocks(text)).count { line in
            String(line).range(of: pattern, options: .regularExpression) != nil
        }
    }

    // MARK: - Code fences

    /// A fenced code block: the zero-based lines of its opener and closer (nil when unclosed).
    struct CodeBlock: Sendable, Hashable {
        var openLine: Int
        var closeLine: Int?
    }

    /// Fenced code blocks (``` or ~~~, three or more), CommonMark style: a closer uses the same
    /// character, at least as many of it, and nothing after.
    static func codeBlocks(in text: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        var open: (line: Int, character: Character, length: Int)?
        for (index, line) in lines(text).enumerated() {
            let content = line.drop { $0 == " " }
            guard line.count - content.count <= 3, let marker = content.first, marker == "`" || marker == "~" else {
                continue
            }
            let run = content.prefix { $0 == marker }
            guard run.count >= 3 else { continue }
            let rest = content.dropFirst(run.count)
            if let current = open {
                if marker == current.character, run.count >= current.length, rest.allSatisfy(\.isWhitespace) {
                    blocks.append(CodeBlock(openLine: current.line, closeLine: index))
                    open = nil
                }
            } else if !(marker == "`" && rest.contains("`")) {
                // A backtick fence's info string cannot contain a backtick; such a line is inline code.
                open = (index, marker, run.count)
            }
        }
        if let current = open {
            blocks.append(CodeBlock(openLine: current.line, closeLine: nil))
        }
        return blocks
    }

    /// Whether one code block spans the whole text, from its first non-blank line to its last.
    static func isWhollyFenced(_ text: String) -> Bool {
        let allLines = lines(text)
        guard let first = allLines.firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }),
              let last = allLines.lastIndex(where: { !$0.allSatisfy(\.isWhitespace) }),
              let block = codeBlocks(in: text).first
        else { return false }
        return block.openLine == first && block.closeLine == last
    }

    /// The text with every fenced code block removed.
    static func textWithoutCodeBlocks(_ text: String) -> String {
        let blocks = codeBlocks(in: text)
        guard !blocks.isEmpty else { return text }
        let allLines = lines(text)
        var keep = [Bool](repeating: true, count: allLines.count)
        for block in blocks {
            let end = block.closeLine ?? allLines.count - 1
            for index in block.openLine...end { keep[index] = false }
        }
        return zip(allLines, keep).filter(\.1).map { String($0.0) }.joined(separator: "\n")
    }

    // MARK: - Language

    /// The text the language is judged on: no code blocks, inline code, tags, template variables
    /// or URLs.
    static func proseForLanguage(_ text: String) -> String {
        var prose = textWithoutCodeBlocks(text)
        let patterns = [
            #"`[^`\n]*`"#,                                 // inline code
            #"</?[A-Za-z_][\w:.-]*(\s[^<>]*)?/?>"#,         // XML/HTML tags
            #"\{\{[^{}]*\}\}|\{[A-Za-z_]\w*\}|<<[^<>]*>>"#, // template variables
            #"\$[A-Z_][A-Z0-9_]*|%[sd@]"#,                  // $VAR, %s
            #"https?://\S+"#,                               // URLs
        ]
        for pattern in patterns {
            prose = prose.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return prose
    }

    /// One language the recognizer considered, with its probability (0–1).
    struct LanguageHypothesis: Sendable, Hashable {
        var code: String
        var probability: Double
    }

    /// What `NLLanguageRecognizer` made of a text.
    struct LanguageGuess: Sendable, Hashable {
        /// BCP-47 code, e.g. `en`, `es`; nil when the recognizer could not tell.
        var dominant: String?
        /// The top hypotheses, most likely first.
        var hypotheses: [LanguageHypothesis]

        /// "es 0.91, pt 0.05" for check details.
        var summary: String {
            hypotheses.map { "\($0.code) \(String(format: "%.2f", $0.probability))" }.joined(separator: ", ")
        }
    }

    /// `NLLanguageRecognizer` on `proseForLanguage(text)`.
    static func language(of text: String) -> LanguageGuess {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(proseForLanguage(text))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .map { LanguageHypothesis(code: $0.key.rawValue, probability: $0.value) }
            .sorted { $0.probability > $1.probability }
        return LanguageGuess(dominant: recognizer.dominantLanguage?.rawValue, hypotheses: hypotheses)
    }

    /// Letters in the prose; below a few words the recognizer is guessing.
    static func letterCount(_ text: String) -> Int {
        proseForLanguage(text).count(where: \.isLetter)
    }

    /// The primary subtag: `es` for `es-ES`.
    static func primaryLanguage(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    // MARK: - Variables and fill-ins

    /// `{{…}}` variables, with inner whitespace kept as written.
    static func mustacheVariables(_ text: String) -> Set<String> {
        matches(of: #"\{\{[^{}\n]+\}\}"#, in: text)
    }

    /// `[…]` fill-ins outside code: not empty, not a checkbox, not a Markdown link.
    static func fillIns(_ text: String) -> Set<String> {
        matches(of: #"\[(?![ xX]?\])[^\[\]\n]{2,100}\](?![(\[])"#, in: textWithoutCodeBlocks(text))
    }

    // MARK: - Regular expressions

    /// Every match of an ICU regular expression; empty when the pattern is invalid.
    static func matches(of pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }

    /// The first match of an ICU regular expression, or nil.
    static func firstMatch(of regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else {
            return nil
        }
        return String(text[found])
    }

    /// Whether `token` occurs in `text` with no letter, digit or underscore on either side.
    static func containsToken(_ token: String, in text: String) -> Bool {
        guard !token.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}_])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Collapses whitespace and shortens, for check details.
    static func excerpt(_ text: some StringProtocol, limit: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit - 1)) + "…"
    }
}
