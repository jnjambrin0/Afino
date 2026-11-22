import Foundation
import PIDesign

/// Turns bursty streamed text into an even flow: new text waits here and leaves in small runs,
/// one run per drain tick (`EmberDesign.Stream.drainInterval`).
///
/// Pure and clock-free: the owner calls `tick()` on its own clock, so every pacing rule is
/// testable without time.
///
/// - Each tick releases `EmberDesign.Stream.releaseCount(pending:)` characters
///   (`max(2, ceil(pending × 0.2))`), counted in grapheme clusters, so a release never splits an
///   emoji, a combining sequence or a CRLF.
/// - A release that would end inside a word is extended to the next whitespace when one lies
///   within `wordBoundaryLookahead` characters, so words appear whole.
/// - No delivery waits more than `StreamLocalTokens.maximumLagTicks` ticks (within
///   `StreamLocalTokens.maximumLag`): the release grows as a delivery's deadline approaches,
///   which keeps the flow even through a burst.
/// - A release never ends inside a line's opening markup (`#`, fences) while more text is on its
///   way, so the styler can decide the line's metrics (heading weight, code font) as soon as the
///   line appears, and a line on screen never reflows.
///
/// Positions are exact UTF-8 prefixes: what is revealed is always a code-unit-exact prefix of the
/// text given, never a canonically-equivalent rewrite.
nonisolated struct StreamRevealBuffer: Sendable {
    /// What `receive(_:)` did with new text.
    enum Change: Equatable, Sendable {
        /// The text is what the buffer already holds.
        case unchanged
        /// The text extends what was given before; the new part waits for ticks.
        case appended
        /// The text is not an extension (a new version, a reset): everything is revealed at once.
        case replaced
    }

    /// One tick's worth of text, to append to the display.
    struct Release: Equatable, Sendable {
        let text: String
        /// Where `text` starts in the revealed text, in UTF-16 code units (the text storage's
        /// indexing).
        let utf16Offset: Int

        var utf16Length: Int { text.utf16.count }
        var utf16Range: NSRange { NSRange(location: utf16Offset, length: utf16Length) }
    }

    private struct Delivery: Sendable {
        /// The UTF-8 offset where the delivered text ends.
        let endUTF8: Int
        /// The tick by which all of it must be revealed.
        let deadline: Int
    }

    /// Everything given so far: revealed text followed by pending text.
    private(set) var text = ""
    /// The revealed prefix's length in UTF-8 code units.
    private var revealedUTF8 = 0
    /// The revealed prefix's length in UTF-16 code units (what the text storage holds).
    private(set) var revealedUTF16 = 0
    /// Grapheme clusters waiting to be revealed.
    private(set) var pendingCount = 0
    /// Ticks so far: the clock that delivery deadlines are counted on.
    private var tickCount = 0
    /// After `finish()`: the stream is over, so nothing is held back for line-start markup.
    private(set) var isFinishing = false
    private var deliveries: [Delivery] = []

    /// Every delivery is fully revealed within this many ticks of arriving.
    let maximumLagTicks: Int
    /// A release may run on this many characters to end after whitespace.
    let wordBoundaryLookahead: Int

    init(
        maximumLagTicks: Int = StreamLocalTokens.maximumLagTicks,
        wordBoundaryLookahead: Int = EmberDesign.Stream.wordBoundaryLookahead
    ) {
        self.maximumLagTicks = max(1, maximumLagTicks)
        self.wordBoundaryLookahead = max(0, wordBoundaryLookahead)
    }

    var revealedText: Substring { text[..<revealedEnd] }

    /// Whether everything given so far is revealed.
    var isDrained: Bool { revealedUTF8 == text.utf8.count }

    private var revealedEnd: String.Index {
        text.utf8.index(text.utf8.startIndex, offsetBy: revealedUTF8)
    }

    // MARK: Input

    /// Takes the latest full text of a stream. Text that extends what the buffer holds is queued;
    /// anything else replaces the content and is revealed at once.
    mutating func receive(_ newText: String) -> Change {
        if newText.utf8.count == text.utf8.count, Self.hasPrefix(newText, text) {
            return .unchanged
        }
        guard newText.utf8.count > text.utf8.count, Self.hasPrefix(newText, text) else {
            reset(to: newText)
            return .replaced
        }
        text = Self.native(newText)
        deliveries.append(Delivery(endUTF8: text.utf8.count, deadline: tickCount + maximumLagTicks))
        pendingCount = text.distance(from: revealedEnd, to: text.endIndex)
        return .appended
    }

    /// Replaces everything with `newText`, all of it revealed.
    mutating func reset(to newText: String) {
        text = Self.native(newText)
        revealedUTF8 = text.utf8.count
        revealedUTF16 = text.utf16.count
        pendingCount = 0
        deliveries = []
        isFinishing = false
    }

    /// The stream ended: everything pending leaves within `maximumLagTicks` ticks (every
    /// delivery's deadline already falls inside that window), and nothing is held back any more.
    mutating func finish() {
        isFinishing = true
    }

    // MARK: Output

    /// One drain tick: the run to reveal now, or `nil` when nothing leaves on this tick.
    mutating func tick() -> Release? {
        tickCount += 1
        guard !isDrained else {
            deliveries = []
            return nil
        }
        let start = revealedEnd
        var count = EmberDesign.Stream.releaseCount(pending: pendingCount)
        count = max(count, deadlineCount(from: start))
        count = min(count, pendingCount)

        var end = start
        for _ in 0..<count where end < text.endIndex {
            end = text.index(after: end)
        }
        end = preferringWordBoundary(end)
        end = respectingLineStartMarkup(end, releaseStart: start)
        guard end > start else { return nil }
        return reveal(upTo: end)
    }

    /// Everything pending, at once.
    mutating func flush() -> Release? {
        guard !isDrained else { return nil }
        return reveal(upTo: text.endIndex)
    }

    private mutating func reveal(upTo end: String.Index) -> Release {
        let start = revealedEnd
        let run = String(text[start..<end])
        let release = Release(text: run, utf16Offset: revealedUTF16)
        revealedUTF8 = text.utf8.distance(from: text.utf8.startIndex, to: end)
        revealedUTF16 += run.utf16.count
        pendingCount = text.distance(from: end, to: text.endIndex)
        deliveries.removeAll { $0.endUTF8 <= revealedUTF8 }
        return release
    }

    // MARK: Rules

    /// The smallest release that keeps every pending delivery on schedule: each must be fully
    /// revealed by its deadline, spread evenly over the ticks it has left.
    private func deadlineCount(from start: String.Index) -> Int {
        var needed = 0
        var cursor = start
        var cumulative = 0
        for delivery in deliveries where delivery.endUTF8 > revealedUTF8 {
            let end = text.utf8.index(text.utf8.startIndex, offsetBy: delivery.endUTF8)
            if end > cursor {
                cumulative += text.distance(from: cursor, to: end)
                cursor = end
            }
            let ticksLeft = max(1, delivery.deadline - tickCount + 1)
            needed = max(needed, (cumulative + ticksLeft - 1) / ticksLeft)
        }
        return needed
    }

    /// Extends `end` to just after the next whitespace when one lies within the lookahead.
    private func preferringWordBoundary(_ end: String.Index) -> String.Index {
        guard end < text.endIndex, end > text.startIndex else { return end }
        if text[text.index(before: end)].isWhitespace {
            return end
        }
        var probe = end
        var steps = 0
        while probe < text.endIndex, steps < wordBoundaryLookahead {
            let character = text[probe]
            probe = text.index(after: probe)
            steps += 1
            if character.isWhitespace {
                return probe
            }
        }
        return end
    }

    /// A line's metrics are decided by its first characters (`# ` makes a heading, three
    /// backticks or tildes open a fence), so a release never ends between a line's start and the
    /// character that decides it. If that character is already here, the release takes it;
    /// otherwise the line waits for more text (unless the stream is finishing).
    private func respectingLineStartMarkup(_ end: String.Index, releaseStart: String.Index) -> String.Index {
        guard let lineStart = lineStart(before: end), lineStart < end else { return end }

        // Up to three leading spaces decide nothing (and draw nothing).
        var cursor = lineStart
        var spaces = 0
        while cursor < end, text[cursor] == " ", spaces < 3 {
            cursor = text.index(after: cursor)
            spaces += 1
        }
        guard cursor < end, let marker = Self.lineMarker(text[cursor]) else { return end }
        let markerStart = cursor

        var run = 0
        var probe = cursor
        while probe < text.endIndex {
            let character = text[probe]
            probe = text.index(after: probe)
            guard Self.lineMarker(character) == marker else {
                // The first other character decides the line: release it with the markup.
                return max(end, probe)
            }
            run += 1
            if marker == "#" ? run > Self.maximumHeadingLevel : run >= Self.fenceLength {
                return max(end, probe)
            }
        }
        // The deciding character has not arrived yet.
        return isFinishing ? end : holdBack(markerStart, releaseStart, end)
    }

    private static let maximumHeadingLevel = 6
    private static let fenceLength = 3

    /// `#`, a backtick or a tilde: the characters that can open metric-changing markup.
    private static func lineMarker(_ character: Character) -> Unicode.Scalar? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
              scalar == "#" || scalar == "`" || scalar == "~" else {
            return nil
        }
        return scalar
    }

    /// Ends the release just before the undecided markup (possibly releasing nothing this tick).
    /// If some of that markup is already shown (a release forced it out), the release stands.
    private func holdBack(_ markerStart: String.Index, _ releaseStart: String.Index, _ end: String.Index) -> String.Index {
        markerStart >= releaseStart ? markerStart : end
    }

    /// The start of the line that `end` falls in, when only spaces and markup characters lie
    /// between the two (only a line's first characters matter here).
    private func lineStart(before end: String.Index) -> String.Index? {
        var cursor = end
        var steps = 0
        let limit = 3 + Self.maximumHeadingLevel + 1
        while cursor > text.startIndex, steps <= limit {
            let previous = text.index(before: cursor)
            if text[previous].isNewline {
                return cursor
            }
            let character = text[previous]
            guard character == " " || character == "#" || character == "`" || character == "~" else {
                return nil
            }
            cursor = previous
            steps += 1
        }
        return cursor == text.startIndex ? cursor : nil
    }

    /// Whether `string` starts with exactly the code units of `prefix` (no Unicode equivalence:
    /// "é" and "e\u{301}" differ). A byte comparison for native strings.
    static func hasPrefix(_ string: String, _ prefix: String) -> Bool {
        let count = prefix.utf8.count
        guard string.utf8.count >= count else { return false }
        let fast = string.utf8.withContiguousStorageIfAvailable { whole in
            prefix.utf8.withContiguousStorageIfAvailable { part in
                count == 0 || memcmp(whole.baseAddress!, part.baseAddress!, count) == 0
            }
        }
        if let fast = fast ?? nil {
            return fast
        }
        return string.utf8.starts(with: prefix.utf8)
    }

    /// A copy in contiguous native UTF-8, so `hasPrefix` and the UTF-8 offsets take the fast path.
    private static func native(_ string: String) -> String {
        var copy = string
        copy.makeContiguousUTF8()
        return copy
    }
}
