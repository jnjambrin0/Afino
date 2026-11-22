import AppKit
@testable import PIApp
import Testing

/// The raw-prompt tint: tags, Markdown markers, headings, fences and inline code, as ranges only.
struct PromptSyntaxStylerTests {
    private typealias Kind = PromptSyntaxStyler.Kind

    /// The substrings styled with `kind`.
    private func strings(_ kind: Kind, in text: String, provisional: Bool = false) -> [String] {
        let result = PromptSyntaxStyler.style(text, provisionalTail: provisional)
        let string = text as NSString
        return result.spans.filter { $0.kind == kind }.map { string.substring(with: $0.range) }
    }

    /// The kinds covering each UTF-16 unit.
    private func kindMap(_ spans: [PromptSyntaxStyler.Span], length: Int, offset: Int = 0, into map: inout [Set<Kind>]) {
        for index in offset..<length {
            map[index] = []
        }
        for span in spans {
            for index in span.range.location..<NSMaxRange(span.range) {
                map[offset + index].insert(span.kind)
            }
        }
    }

    private static let corpus = [
        """
        # Role
        You are a <role>senior engineer</role>. Use `snake_case` and **bold** words.

        ## Steps
        1. Read the <document> carefully.
        - First * item
        * Second item
        > A quote
        ---
        ```python
        def f(x):  # not a heading
            return x * 2  <not a tag>
        ```
        After the fence: a < b and c > d, <-arrow, 2 * 3.
        </document>
        """,
        "Plain text with no markup at all.\r\nSecond line.\r\n",
        "~~~\nunclosed tilde fence\n# still code",
        "``code with ` inside`` and `unclosed",
        "#hashtag\n####### seven\n    # indented code\n   # three spaces\n#",
    ]

    // MARK: Tags

    @Test func tintsXMLStyleTags() {
        let text = "<document>\nHello <b class=\"x\">there</b> and <br/>\n</examples>"
        #expect(strings(.markup, in: text) == ["<document>", "<b class=\"x\">", "</b>", "<br/>", "</examples>"])
    }

    @Test func leavesComparisonsAndArrowsAlone() {
        #expect(strings(.markup, in: "a < b, c<-d, x <3 and 1<2").isEmpty)
    }

    @Test func stylesAnUnfinishedTagAtTheTailOnlyWhileStreaming() {
        #expect(strings(.markup, in: "Read the <docu", provisional: true) == ["<docu"])
        #expect(strings(.markup, in: "Read the <docu", provisional: false).isEmpty)
        #expect(strings(.markup, in: "Read the <", provisional: true) == ["<"])
    }

    // MARK: Headings

    @Test func headingLinesAreSemiboldWithTheirHashesTinted() {
        let text = "# Title\nBody\n### Sub <tag>"
        #expect(strings(.heading, in: text) == ["# Title\n", "### Sub <tag>"])
        #expect(strings(.markup, in: text) == ["#", "###", "<tag>"])
    }

    @Test func notEverythingWithAHashIsAHeading() {
        let text = "#hashtag\n####### seven\n    # four spaces\n   # three spaces"
        #expect(strings(.heading, in: text) == ["   # three spaces"])
    }

    // MARK: Fences

    @Test func anOpenFenceRunsToTheEndAndCarriesItsState() {
        let text = "Intro\n```swift\nlet x = \"<tag>\" // # no heading\n"
        let result = PromptSyntaxStyler.style(text)
        let string = text as NSString
        let code = result.spans.filter { $0.kind == .codeBlock }.map { string.substring(with: $0.range) }
        #expect(code == ["```swift\n", "let x = \"<tag>\" // # no heading\n"])
        // Nothing inside the block is tinted as markup except the fence line itself.
        #expect(strings(.markup, in: text) == ["```swift"])
        #expect(result.stateAtLastLine.fence == PromptSyntaxStyler.State.Fence(marker: 0x60, length: 3))
        #expect(result.lastLineStart == string.length)

        // The rest of the stream, styled from that state, closes the block.
        let tail = "```\nAfter `x`"
        let next = PromptSyntaxStyler.style(tail, from: result.stateAtLastLine)
        let tailString = tail as NSString
        #expect(next.spans.filter { $0.kind == .codeBlock }.map { tailString.substring(with: $0.range) } == ["```\n"])
        #expect(next.stateAtLastLine.fence == nil)
        #expect(next.spans.filter { $0.kind == .inlineCode }.map { tailString.substring(with: $0.range) } == ["x"])
    }

    @Test func aShorterFenceDoesNotCloseALongerOne() {
        let text = "````\ncode\n```\nstill code\n````\nout"
        let result = PromptSyntaxStyler.style(text)
        #expect(result.stateAtLastLine.fence == nil)
        let string = text as NSString
        let code = result.spans.filter { $0.kind == .codeBlock }.map { string.substring(with: $0.range) }
        #expect(code == ["````\n", "code\n", "```\n", "still code\n", "````\n"])
    }

    // MARK: Inline code and markers

    @Test func inlineCodeIsTheTextBetweenTintedBackticks() {
        let text = "Use `foo` and ``a`b`` but `unclosed"
        #expect(strings(.inlineCode, in: text) == ["foo", "a`b"])
        #expect(strings(.markup, in: text) == ["`", "`", "``", "``", "`"])
        #expect(strings(.heading, in: text).isEmpty)
        #expect(strings(.codeBlock, in: text).isEmpty)
    }

    @Test func tintsListBulletsQuotesRulesAndEmphasis() {
        let text = "- one\n* two\n+ three\n12. four\n> quote\n---\nsome **bold** and *it* but 2 * 3"
        #expect(strings(.markup, in: text) == ["-", "*", "+", "12.", ">", "---", "**", "**", "*", "*"])
    }

    // MARK: Text integrity

    @Test func stylingNeverChangesTheText() {
        for text in Self.corpus {
            for provisional in [false, true] {
                let result = PromptSyntaxStyler.style(text, provisionalTail: provisional)
                let length = text.utf16.count
                #expect(result.spans.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length && $0.range.length > 0 })

                let storage = NSTextStorage(string: text)
                StreamTextStyle.apply(result.spans, to: storage, in: NSRange(location: 0, length: storage.length))
                #expect(storage.string.utf16.elementsEqual(text.utf16))
            }
        }
    }

    @Test func stylingTheTailFromItsStateMatchesStylingEverything() {
        for text in Self.corpus {
            let units = Array(text.utf16)
            let full = PromptSyntaxStyler.style(text)
            var expected = Array(repeating: Set<Kind>(), count: units.count)
            kindMap(full.spans, length: units.count, into: &expected)

            // Grow the text one scalar at a time, restyling from the last line like the view does.
            var map = Array(repeating: Set<Kind>(), count: units.count)
            var lineStart = 0
            var state = PromptSyntaxStyler.State()
            var length = 0
            for scalar in text.unicodeScalars {
                length += String(scalar).utf16.count
                let tail = String(utf16CodeUnits: Array(units[lineStart..<length]), count: length - lineStart)
                let isLast = length == units.count
                let result = PromptSyntaxStyler.style(tail, from: state, provisionalTail: !isLast)
                kindMap(result.spans, length: length, offset: lineStart, into: &map)
                lineStart += result.lastLineStart
                state = result.stateAtLastLine
            }
            #expect(map == expected, "incremental styling diverged for \(text.debugDescription)")
        }
    }

    @Test func metricStylesNeverChangeOnceTextIsShownWhenStreamedThroughTheBuffer() {
        let text = """
        Intro line
        # Heading arrives
        ```swift
        let code = true
        ```
        ## Another
        Body with <tag> and `code`.
        """
        let scalars = Array(text.unicodeScalars)
        var random = SplitMix64(seed: 7)
        for _ in 0..<20 {
            var buffer = StreamRevealBuffer()
            var metric: [Kind?] = []
            var lineStart = 0
            var state = PromptSyntaxStyler.State()
            var revealed = ""
            var delivered = 0
            while delivered < scalars.count || !buffer.isDrained {
                if delivered < scalars.count {
                    delivered = min(scalars.count, delivered + Int(random.next() % 5) + 1)
                    var view = String.UnicodeScalarView()
                    view.append(contentsOf: scalars[..<delivered])
                    _ = buffer.receive(String(view))
                } else {
                    buffer.finish()
                }
                guard let release = buffer.tick() else { continue }
                revealed += release.text
                let units = Array(revealed.utf16)
                let tail = String(utf16CodeUnits: Array(units[lineStart...]), count: units.count - lineStart)
                let result = PromptSyntaxStyler.style(tail, from: state, provisionalTail: true)
                var current = Array(repeating: Kind?.none, count: units.count)
                for index in 0..<min(metric.count, lineStart) {
                    current[index] = metric[index]
                }
                for span in result.spans where span.kind == .heading || span.kind == .codeBlock {
                    for index in span.range.location..<NSMaxRange(span.range) {
                        current[lineStart + index] = span.kind
                    }
                }
                for index in 0..<metric.count where index >= lineStart {
                    #expect(current[index] == metric[index], "metrics changed at \(index) in \(revealed.debugDescription)")
                }
                metric = current
                lineStart += result.lastLineStart
                state = result.stateAtLastLine
            }
        }
    }
}
