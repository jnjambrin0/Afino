import Foundation

/// Finds the structure of a raw prompt so the result well can tint it, without rendering it: the
/// output is ranges and kinds only, so no character is ever hidden, replaced or reordered and what
/// is selected and copied is exactly the model's text.
///
/// - `.markup`: XML-style tags (`<document>`, `</examples>`), Markdown markers (`#` of a heading,
///   list bullets, `>` quotes, emphasis `*`, backticks, rules) and whole fence lines.
/// - `.heading`: an ATX heading line (`# …`), drawn semibold at the body size.
/// - `.codeBlock`: the lines of a fenced code block, fences included, drawn monospaced.
/// - `.inlineCode`: the text between backticks. The well leaves it in the body font and colour;
///   only the backticks around it are tinted.
///
/// Metric-changing kinds (`.heading`, `.codeBlock`) are decided by a line's first characters and
/// the fence state at its start, never by anything later on the line, so text streaming onto a
/// line never changes the metrics of the part already shown. Spans are UTF-16 ranges (the text
/// storage's indexing) relative to the styled string.
///
/// Incremental: style the tail of a growing text from the start of its last line, passing the
/// state `style` returned for that line, and the result equals styling the whole text.
nonisolated enum PromptSyntaxStyler {
    /// What a span of text is (see the type's notes for how each is drawn).
    enum Kind: Equatable, Sendable {
        case markup
        case heading
        case codeBlock
        case inlineCode
    }

    /// A kind over a UTF-16 range of the styled string.
    struct Span: Equatable, Sendable {
        let kind: Kind
        let range: NSRange
    }

    /// What a line inherits from the lines above it.
    struct State: Equatable, Sendable {
        /// The open fence (its character and length), if the line is inside a code block.
        var fence: Fence?

        struct Fence: Equatable, Sendable {
            let marker: UInt16
            let length: Int
        }
    }

    /// The spans of one pass, and where the next pass over a longer text resumes.
    struct Result: Equatable, Sendable {
        let spans: [Span]
        /// Where the last line starts (UTF-16 offset). Text appended later can only change this
        /// line and what follows, so the next pass starts here…
        let lastLineStart: Int
        /// …with this state.
        let stateAtLastLine: State
    }

    /// Styles `text`, which starts at a line start with `state`.
    ///
    /// - Parameter provisionalTail: The text is still growing: markup that is plausibly
    ///   unfinished at the very end (`<docu`, a lone bullet) is styled as if it will complete,
    ///   so it does not change colour when the rest arrives. Pass `false` for final text.
    static func style(_ text: String, from state: State = State(), provisionalTail: Bool = false) -> Result {
        let units = Array(text.utf16)
        var scanner = Scanner(units: units, provisionalTail: provisionalTail)
        var state = state
        var lineStart = 0
        var lastLineStart = 0
        var stateAtLastLine = state

        while true {
            lastLineStart = lineStart
            stateAtLastLine = state
            let (contentEnd, lineEnd) = lineBounds(units, from: lineStart)
            let isLastLine = lineEnd == units.count && contentEnd == lineEnd
            scanner.styleLine(start: lineStart, contentEnd: contentEnd, lineEnd: lineEnd, isTail: isLastLine, state: &state)
            if lineEnd >= units.count {
                if contentEnd < lineEnd {
                    // The text ends with a line break: the last line is the empty one after it.
                    lastLineStart = units.count
                    stateAtLastLine = state
                }
                break
            }
            lineStart = lineEnd
        }
        return Result(spans: scanner.spans, lastLineStart: lastLineStart, stateAtLastLine: stateAtLastLine)
    }

    // MARK: Lines

    private static let newline: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D

    /// The end of a line's content and the start of the next line (after its terminator).
    private static func lineBounds(_ units: [UInt16], from start: Int) -> (contentEnd: Int, lineEnd: Int) {
        var index = start
        while index < units.count {
            let unit = units[index]
            if unit == newline {
                return (index, index + 1)
            }
            if unit == carriageReturn {
                let next = index + 1
                if next < units.count, units[next] == newline {
                    return (index, next + 1)
                }
                return (index, next)
            }
            index += 1
        }
        return (units.count, units.count)
    }

    /// Styles one line at a time over the text's UTF-16 units, collecting spans.
    private struct Scanner {
        let units: [UInt16]
        let provisionalTail: Bool
        var spans: [Span] = []

        init(units: [UInt16], provisionalTail: Bool) {
            self.units = units
            self.provisionalTail = provisionalTail
        }

        private static let space: UInt16 = 0x20
        private static let tab: UInt16 = 0x09
        private static let hash: UInt16 = 0x23
        private static let backtick: UInt16 = 0x60
        private static let tilde: UInt16 = 0x7E
        private static let less: UInt16 = 0x3C
        private static let greater: UInt16 = 0x3E
        private static let slash: UInt16 = 0x2F
        private static let star: UInt16 = 0x2A
        private static let dash: UInt16 = 0x2D
        private static let plus: UInt16 = 0x2B
        private static let underscore: UInt16 = 0x5F
        private static let period: UInt16 = 0x2E
        private static let closeParen: UInt16 = 0x29

        private static let maximumHeadingLevel = 6
        private static let fenceLength = 3
        private static let maximumIndent = 3
        private static let maximumListNumberDigits = 9

        private mutating func add(_ kind: Kind, _ lower: Int, _ upper: Int) {
            guard upper > lower else { return }
            spans.append(Span(kind: kind, range: NSRange(location: lower, length: upper - lower)))
        }

        private func isBlank(_ unit: UInt16) -> Bool {
            unit == Self.space || unit == Self.tab
        }

        private func run(of unit: UInt16, from start: Int, to end: Int) -> Int {
            var index = start
            while index < end, units[index] == unit {
                index += 1
            }
            return index - start
        }

        /// The first non-space position, if the line is indented by at most three spaces.
        private func markupStart(_ start: Int, _ end: Int) -> Int? {
            let indent = run(of: Self.space, from: start, to: end)
            return indent <= Self.maximumIndent ? start + indent : nil
        }

        mutating func styleLine(start: Int, contentEnd: Int, lineEnd: Int, isTail: Bool, state: inout State) {
            if let fence = state.fence {
                add(.codeBlock, start, lineEnd)
                if let first = markupStart(start, contentEnd), first < contentEnd, units[first] == fence.marker {
                    let length = run(of: fence.marker, from: first, to: contentEnd)
                    let rest = units[(first + length)..<contentEnd]
                    if length >= fence.length, rest.allSatisfy(isBlank) {
                        add(.markup, first, contentEnd)
                        state.fence = nil
                    }
                }
                return
            }

            guard let first = markupStart(start, contentEnd), first < contentEnd else {
                styleInline(start, contentEnd, isTail: isTail)
                return
            }
            let unit = units[first]

            // A fence opens the block; the fence line itself is code-styled too.
            if unit == Self.backtick || unit == Self.tilde {
                let length = run(of: unit, from: first, to: contentEnd)
                let info = units[(first + length)..<contentEnd]
                if length >= Self.fenceLength, unit == Self.tilde || !info.contains(Self.backtick) {
                    add(.codeBlock, start, lineEnd)
                    add(.markup, first, contentEnd)
                    state.fence = State.Fence(marker: unit, length: length)
                    return
                }
            }

            if unit == Self.hash {
                let level = run(of: Self.hash, from: first, to: contentEnd)
                let after = first + level
                if level <= Self.maximumHeadingLevel, after == contentEnd || isBlank(units[after]) {
                    add(.heading, start, lineEnd)
                    add(.markup, first, after)
                    styleInline(after, contentEnd, isTail: isTail)
                    return
                }
            }

            if isRule(first, contentEnd) {
                add(.markup, first, contentEnd)
                return
            }

            let body = styleLineMarker(start, contentEnd, isTail: isTail)
            styleInline(body, contentEnd, isTail: isTail)
        }

        /// `---`, `***` or `___` (three or more, spaces allowed) and nothing else.
        private func isRule(_ start: Int, _ end: Int) -> Bool {
            let unit = units[start]
            guard unit == Self.dash || unit == Self.star || unit == Self.underscore else { return false }
            var count = 0
            for index in start..<end {
                if units[index] == unit {
                    count += 1
                } else if !isBlank(units[index]) {
                    return false
                }
            }
            return count >= Self.fenceLength
        }

        /// A bullet (`-`, `*`, `+`), an ordered-list number (`1.`) or a quote (`>`) at the start
        /// of the line, after any indentation. Returns where the rest of the line starts.
        private mutating func styleLineMarker(_ start: Int, _ end: Int, isTail: Bool) -> Int {
            var first = start
            while first < end, isBlank(units[first]) {
                first += 1
            }
            guard first < end else { return start }
            let unit = units[first]
            let next = first + 1
            let followedByBlank = next < end && isBlank(units[next])
            let atProvisionalEnd = next == end && isTail && provisionalTail

            if unit == Self.dash || unit == Self.star || unit == Self.plus || unit == Self.greater {
                if followedByBlank || atProvisionalEnd || (unit == Self.greater && next == end) {
                    add(.markup, first, next)
                    return next
                }
                return start
            }

            var digitsEnd = first
            while digitsEnd < end, digitsEnd - first < Self.maximumListNumberDigits,
                  (0x30...0x39).contains(units[digitsEnd]) {
                digitsEnd += 1
            }
            if digitsEnd > first, digitsEnd < end, units[digitsEnd] == Self.period || units[digitsEnd] == Self.closeParen {
                let after = digitsEnd + 1
                if (after < end && isBlank(units[after])) || (after == end && isTail && provisionalTail) {
                    add(.markup, first, after)
                    return after
                }
            }
            return start
        }

        /// Backtick code, tags and emphasis markers inside a line.
        private mutating func styleInline(_ start: Int, _ end: Int, isTail: Bool) {
            var index = start
            while index < end {
                let unit = units[index]
                switch unit {
                case Self.backtick:
                    index = styleCodeSpan(at: index, end)
                case Self.less:
                    index = styleTag(at: index, end, isTail: isTail)
                case Self.star:
                    let length = run(of: Self.star, from: index, to: end)
                    let before = index > start ? units[index - 1] : nil
                    let after = index + length < end ? units[index + length] : nil
                    let leftFlanking = after.map { !isBlank($0) } ?? false
                    let rightFlanking = before.map { !isBlank($0) } ?? false
                    let provisional = after == nil && isTail && provisionalTail
                    if leftFlanking || rightFlanking || provisional {
                        add(.markup, index, index + length)
                    }
                    index += length
                default:
                    index += 1
                }
            }
        }

        /// A run of backticks opens a code span closed by a run of the same length on the same
        /// line. The backticks are markup either way; the text between them is inline code.
        private mutating func styleCodeSpan(at start: Int, _ end: Int) -> Int {
            let length = run(of: Self.backtick, from: start, to: end)
            var search = start + length
            while search < end {
                if units[search] == Self.backtick {
                    let closing = run(of: Self.backtick, from: search, to: end)
                    if closing == length {
                        add(.markup, start, start + length)
                        add(.inlineCode, start + length, search)
                        add(.markup, search, search + closing)
                        return search + closing
                    }
                    search += closing
                } else {
                    search += 1
                }
            }
            add(.markup, start, start + length)
            return start + length
        }

        /// `<name …>`, `</name>` and `<name/>` where `name` starts with an ASCII letter. Anything
        /// else with `<` (`a < b`, `<-`) stays plain text. An unclosed tag at the very end of
        /// growing text is styled provisionally.
        private mutating func styleTag(at start: Int, _ end: Int, isTail: Bool) -> Int {
            var cursor = start + 1
            if cursor < end, units[cursor] == Self.slash {
                cursor += 1
            }
            guard cursor < end, Self.isASCIILetter(units[cursor]) else {
                if cursor == end, isTail, provisionalTail {
                    add(.markup, start, end)
                    return end
                }
                return start + 1
            }
            while cursor < end {
                let unit = units[cursor]
                if unit == Self.greater {
                    add(.markup, start, cursor + 1)
                    return cursor + 1
                }
                if unit == Self.less {
                    return start + 1
                }
                cursor += 1
            }
            if isTail, provisionalTail {
                add(.markup, start, end)
                return end
            }
            return start + 1
        }

        private static func isASCIILetter(_ unit: UInt16) -> Bool {
            (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
        }
    }
}
