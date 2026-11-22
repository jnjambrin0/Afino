import Foundation

/// Deterministic, minimal clean-up of the engine's reply. It never rejects an output.
///
/// Final text, in order:
/// 1. Line endings normalised to LF; leading and trailing whitespace trimmed.
/// 2. One outer code fence unwrapped, only when the first line opens a fence whose info string is
///    empty, `text`, `txt`, `markdown`, `md`, `plaintext` or `prompt`; the last line is the
///    matching closer (same number of backticks, nothing after them); no line in between is a
///    fence of the same or greater length (so a 4-backtick wrapper may hold ``` blocks); and the
///    draft itself was not wholly fenced.
/// 3. One preface line stripped, only when it starts with "Here is", "Here's", "Aquí tienes" or
///    "Aquí está", contains "prompt", ends with a colon, is followed by a blank line and more
///    content, and the draft did not start with that same line.
///
/// It never touches inner fences, XML tags, brackets, quotes or dashes, never parses JSON, never
/// collapses blank lines and never truncates.
public enum OutputPostProcessor {
    /// The cleaned text and which rules changed it.
    public struct Result: Sendable, Hashable {
        /// The text to show and copy.
        public let text: String
        /// Whether rule 2 removed an outer code fence.
        public let didUnwrapFence: Bool
        /// Whether rule 3 removed a preface line.
        public let didStripPreface: Bool
    }

    /// The text to show and copy once the output is complete.
    public static func finalize(_ output: String, draft: String) -> String {
        process(output, draft: draft).text
    }

    /// `finalize(_:draft:)`, also reporting which rules applied.
    public static func process(_ output: String, draft: String) -> Result {
        var text = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(output))

        let unwrapped = unwrappedFence(of: text, draft: draft)
        if let unwrapped {
            text = TextNormalization.trimmed(unwrapped)
        }

        let withoutPreface = strippedPreface(of: text, draft: draft)
        if let withoutPreface {
            text = withoutPreface
        }

        return Result(text: text, didUnwrapFence: unwrapped != nil, didStripPreface: withoutPreface != nil)
    }

    /// What to show while the output streams in. Create one per run.
    ///
    /// Leading whitespace is dropped, and an opening fence line that may still turn out to wrap the
    /// whole output is hidden (with a trailing line that may become its closer) until the output
    /// proves otherwise. A preface line is not hidden. At completion, show `finalize(_:draft:)`.
    public struct StreamingDisplay: Sendable {
        private let draftIsWhollyFenced: Bool

        public init(draft: String) {
            draftIsWhollyFenced = OutputPostProcessor.isWhollyFenced(draft)
        }

        /// The text to display for everything received so far.
        public func text(for accumulated: String) -> String {
            let normalized = TextNormalization.normalizingLineEndings(accumulated)
            let text = normalized.drop(while: \.isWhitespace)
            guard text.first == "`", !draftIsWhollyFenced else { return String(text) }

            guard let firstBreak = text.firstIndex(of: "\n") else {
                return OutputPostProcessor.couldBecomeWrapperOpener(text) ? "" : String(text)
            }
            guard let opener = OutputPostProcessor.fenceLine(text[..<firstBreak]),
                  OutputPostProcessor.isWrapperOpener(opener)
            else { return String(text) }

            let body = text[text.index(after: firstBreak)...]
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            var visibleEnd = body.endIndex
            for (offset, line) in lines.enumerated() {
                let isBeingWritten = offset == lines.count - 1
                if let fence = OutputPostProcessor.fenceLine(line), fence.length >= opener.length {
                    let onlyBlankAfter = lines[(offset + 1)...].allSatisfy(TextNormalization.isBlank)
                    guard onlyBlankAfter, OutputPostProcessor.isCloser(fence, of: opener) else {
                        // A second fence of this size: the output is not wholly wrapped.
                        return String(text)
                    }
                    visibleEnd = line.startIndex
                    break
                }
                if isBeingWritten, Self.couldBecomeCloser(line, of: opener) {
                    visibleEnd = line.startIndex
                }
            }
            return String(body[..<visibleEnd].drop(while: \.isWhitespace))
        }

        /// A partial last line made only of up to three spaces or tabs and fewer backticks than the
        /// opener.
        private static func couldBecomeCloser(_ line: Substring, of opener: FenceLine) -> Bool {
            let content = line.drop { $0 == " " || $0 == "\t" }
            let indent = line.count - content.count
            return indent <= 3 && !content.isEmpty && content.count < opener.length && content.allSatisfy { $0 == "`" }
        }
    }

    // MARK: - Rules

    /// Info strings that mark a fence as a wrapper around plain prompt text.
    static let wrapperInfoStrings: Set<String> = ["", "text", "txt", "markdown", "md", "plaintext", "prompt"]

    /// Lowercased preface openings. "Here’s" with a typographic apostrophe counts as "Here's".
    static let prefaceOpenings = ["here is", "here's", "here’s", "aquí tienes", "aquí está"]

    /// A line that starts with a run of 3+ backticks, after any indentation.
    struct FenceLine {
        /// Spaces and tabs before the backticks.
        let indent: Int
        /// Number of backticks.
        let length: Int
        /// Everything after the backticks, untrimmed.
        let info: Substring
    }

    /// The line as a fence, or nil when it does not start with three or more backticks.
    static func fenceLine(_ line: Substring) -> FenceLine? {
        var index = line.startIndex
        var indent = 0
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            indent += 1
            index = line.index(after: index)
        }
        var length = 0
        while index < line.endIndex, line[index] == "`" {
            length += 1
            index = line.index(after: index)
        }
        guard length >= 3 else { return nil }
        return FenceLine(indent: indent, length: length, info: line[index...])
    }

    /// An unindented fence whose info string is one of `wrapperInfoStrings`.
    static func isWrapperOpener(_ fence: FenceLine) -> Bool {
        fence.indent == 0
            && !fence.info.contains("`")
            && wrapperInfoStrings.contains(TextNormalization.trimmed(fence.info).lowercased())
    }

    /// A bare fence of the opener's length, indented by at most three spaces or tabs.
    static func isCloser(_ fence: FenceLine, of opener: FenceLine) -> Bool {
        fence.indent <= 3 && fence.length == opener.length && TextNormalization.isBlank(fence.info)
    }

    /// Whether a first line still being written could become a wrapper opener.
    static func couldBecomeWrapperOpener(_ line: Substring) -> Bool {
        let rest = line.drop { $0 == "`" }
        let length = line.count - rest.count
        guard length >= 3 else { return rest.isEmpty }
        guard !rest.contains("`") else { return false }
        let info = TextNormalization.trimmed(rest).lowercased()
        return wrapperInfoStrings.contains { $0.hasPrefix(info) }
    }

    /// The text between the wrapper's fences, or nil when rule 2 does not apply.
    static func unwrappedFence(of text: String, draft: String) -> String? {
        guard text.hasPrefix("```") else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3,
              let opener = fenceLine(lines[0]), isWrapperOpener(opener),
              let closer = fenceLine(lines[lines.count - 1]), isCloser(closer, of: opener)
        else { return nil }

        let interior = lines[1..<(lines.count - 1)]
        let hasInnerFenceOfSameSize = interior.contains { line in
            fenceLine(line).map { $0.length >= opener.length } ?? false
        }
        guard !hasInnerFenceOfSameSize else { return nil }

        let inner = interior.joined(separator: "\n")
        guard !TextNormalization.isBlank(inner), !isWhollyFenced(draft) else { return nil }
        return inner
    }

    /// The text after the preface line, or nil when rule 3 does not apply.
    static func strippedPreface(of text: String, draft: String) -> String? {
        guard let firstBreak = text.firstIndex(of: "\n") else { return nil }
        let firstLine = TextNormalization.trimmed(text[..<firstBreak])
        guard isPrefaceLine(firstLine) else { return nil }

        let afterFirst = text[text.index(after: firstBreak)...]
        let secondLine = afterFirst.prefix { $0 != "\n" }
        guard TextNormalization.isBlank(secondLine), secondLine.endIndex < afterFirst.endIndex else { return nil }

        let rest = TextNormalization.trimmed(afterFirst)
        guard !rest.isEmpty, firstLine != firstLineOfDraft(draft) else { return nil }
        return rest
    }

    static func isPrefaceLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard line.hasSuffix(":"), lowered.contains("prompt") else { return false }
        return prefaceOpenings.contains { opening in
            lowered.hasPrefix(opening) && lowered.dropFirst(opening.count).first?.isWhitespace == true
        }
    }

    /// Whether the draft, trimmed, opens with a fence line and ends with a bare fence line. Kept
    /// loose on purpose: treating a draft as fenced only ever makes the post-processor do less.
    static func isWhollyFenced(_ draft: String) -> Bool {
        let text = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(draft))
        guard let firstBreak = text.firstIndex(of: "\n"),
              let lastBreak = text.lastIndex(of: "\n"),
              fenceLine(text[..<firstBreak]) != nil,
              let closer = fenceLine(text[text.index(after: lastBreak)...])
        else { return false }
        return TextNormalization.isBlank(closer.info)
    }

    private static func firstLineOfDraft(_ draft: String) -> String {
        let text = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(draft))
        return TextNormalization.trimmed(text.prefix { $0 != "\n" })
    }
}
