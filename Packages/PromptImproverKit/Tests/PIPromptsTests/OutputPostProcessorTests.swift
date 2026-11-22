import Testing
@testable import PIPrompts

struct OutputPostProcessorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let label: String
        let output: String
        var draft = "make me a prompt"
        let expected: String
        var unwrapsFence = false
        var stripsPreface = false

        var testDescription: String { label }
    }

    static let fence = "```"
    static let innerCode = "Refactor this function.\n\n```swift\nfunc add(_ a: Int, _ b: Int) -> Int { a + b }\n```\n\nKeep the signature."

    // MARK: - Rule 1: line endings and outer whitespace

    static let normalisation: [Case] = [
        Case(label: "plain text is untouched", output: "Write a haiku about tea.", expected: "Write a haiku about tea."),
        Case(label: "outer whitespace is trimmed", output: "\n\n  Write a haiku.  \n\t\n", expected: "Write a haiku."),
        Case(label: "CRLF and CR become LF", output: "Line one\r\nLine two\rLine three\r\n", expected: "Line one\nLine two\nLine three"),
        Case(label: "empty output stays empty", output: "  \n ", expected: ""),
    ]

    // MARK: - Rule 2: one outer fence

    static let fences: [Case] = [
        Case(label: "bare fence is unwrapped", output: "```\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "text fence is unwrapped", output: "```text\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "txt fence is unwrapped", output: "```txt\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "markdown fence is unwrapped", output: "```markdown\n# Task\nWrite a haiku.\n```", expected: "# Task\nWrite a haiku.", unwrapsFence: true),
        Case(label: "md fence is unwrapped", output: "```md\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "plaintext fence is unwrapped", output: "```plaintext\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "prompt fence is unwrapped", output: "```prompt\nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "info string is case-insensitive", output: "``` Markdown \nWrite a haiku.\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "CRLF wrapped output", output: "\r\n```text\r\nLine one\r\n\r\nLine two\r\n```\r\n", expected: "Line one\n\nLine two", unwrapsFence: true),
        Case(label: "interior is trimmed after unwrapping", output: "```\n\n  Write a haiku.\n\n```", expected: "Write a haiku.", unwrapsFence: true),
        Case(label: "closer may be indented up to three spaces", output: "```\nWrite a haiku.\n   ```", expected: "Write a haiku.", unwrapsFence: true),
        Case(
            label: "4-backtick wrapper around inner ``` blocks is unwrapped, inner fences kept",
            output: "````markdown\n\(innerCode)\n````",
            expected: innerCode,
            unwrapsFence: true
        ),
        Case(label: "swift fence is NOT unwrapped", output: "```swift\nlet x = 1\n```", expected: "```swift\nlet x = 1\n```"),
        Case(label: "python fence is NOT unwrapped", output: "```python\nprint(1)\n```", expected: "```python\nprint(1)\n```"),
        Case(label: "inner fences are returned untouched", output: innerCode, expected: innerCode),
        Case(
            label: "nested same-size fences are NOT unwrapped",
            output: "```\nRefactor this.\n```swift\nlet x = 1\n```\nThanks.\n```",
            expected: "```\nRefactor this.\n```swift\nlet x = 1\n```\nThanks.\n```"
        ),
        Case(
            label: "bare inner fence of the same size blocks unwrapping",
            output: "```\nPart one\n```\n\n```\nPart two\n```",
            expected: "```\nPart one\n```\n\n```\nPart two\n```"
        ),
        Case(
            label: "longer inner fence blocks unwrapping",
            output: "```\nA\n````\nB\n```",
            expected: "```\nA\n````\nB\n```"
        ),
        Case(label: "closer of another size is not a match", output: "```\nWrite a haiku.\n````", expected: "```\nWrite a haiku.\n````"),
        Case(label: "closer with an info string is not a match", output: "```\nWrite a haiku.\n```text", expected: "```\nWrite a haiku.\n```text"),
        Case(label: "missing closer", output: "```\nWrite a haiku.", expected: "```\nWrite a haiku."),
        Case(label: "text after the closer", output: "```\nWrite a haiku.\n```\nThat's it.", expected: "```\nWrite a haiku.\n```\nThat's it."),
        Case(label: "empty fenced block is kept", output: "```\n\n```", expected: "```\n\n```"),
        Case(label: "a lone fence line is kept", output: "```", expected: "```"),
        Case(label: "tilde fences are not wrappers", output: "~~~\nWrite a haiku.\n~~~", expected: "~~~\nWrite a haiku.\n~~~"),
        Case(
            label: "draft that was wholly fenced keeps the output's fence",
            output: "```text\nSummarise the log below.\n```",
            draft: "```\nERROR 42 at boot\n```",
            expected: "```text\nSummarise the log below.\n```"
        ),
        Case(
            label: "draft wholly fenced with a language also blocks unwrapping",
            output: "```\nExplain this code.\n```",
            draft: "  ```js\nconsole.log(1)\n```  ",
            expected: "```\nExplain this code.\n```"
        ),
        Case(
            label: "draft with inner fences only does not block unwrapping",
            output: "```\nExplain this code.\n```",
            draft: "Explain:\n```js\nconsole.log(1)\n```",
            expected: "Explain this code.",
            unwrapsFence: true
        ),
    ]

    // MARK: - Rule 3: one preface line

    static let prefaces: [Case] = [
        Case(label: "Here is … prompt:", output: "Here is the improved prompt:\n\nWrite a haiku.", expected: "Write a haiku.", stripsPreface: true),
        Case(label: "Here's … prompt:", output: "Here's your prompt:\n\nWrite a haiku.", expected: "Write a haiku.", stripsPreface: true),
        Case(label: "Here’s with a typographic apostrophe", output: "Here’s a refined prompt:\n\nWrite a haiku.", expected: "Write a haiku.", stripsPreface: true),
        Case(label: "Spanish: Aquí tienes", output: "Aquí tienes el prompt mejorado:\n\nEscribe un haiku.", expected: "Escribe un haiku.", stripsPreface: true),
        Case(label: "Spanish: Aquí está", output: "Aquí está el prompt:\n\nEscribe un haiku.", expected: "Escribe un haiku.", stripsPreface: true),
        Case(label: "several blank lines after the preface", output: "Here is the prompt:\n\n\n\nWrite a haiku.", expected: "Write a haiku.", stripsPreface: true),
        Case(label: "CRLF preface", output: "Here is the prompt:\r\n\r\nWrite a haiku.\r\n", expected: "Write a haiku.", stripsPreface: true),
        Case(label: "preface without a blank line is kept", output: "Here is the prompt:\nWrite a haiku.", expected: "Here is the prompt:\nWrite a haiku."),
        Case(label: "preface without the word prompt is kept", output: "Here is the improved version:\n\nWrite a haiku.", expected: "Here is the improved version:\n\nWrite a haiku."),
        Case(label: "preface without a colon is kept", output: "Here is the prompt.\n\nWrite a haiku.", expected: "Here is the prompt.\n\nWrite a haiku."),
        Case(label: "preface with nothing after it is kept", output: "Here is the prompt:", expected: "Here is the prompt:"),
        Case(label: "other openings are kept", output: "Sure! Here is the prompt:\n\nWrite a haiku.", expected: "Sure! Here is the prompt:\n\nWrite a haiku."),
        Case(label: "a word that only starts like the opening is kept", output: "Hereisthe prompt:\n\nWrite a haiku.", expected: "Hereisthe prompt:\n\nWrite a haiku."),
        Case(
            label: "only one preface line is stripped",
            output: "Here is the prompt:\n\nHere is the prompt:\n\nWrite a haiku.",
            expected: "Here is the prompt:\n\nWrite a haiku.",
            stripsPreface: true
        ),
        Case(
            label: "a preface the draft itself opened with is kept",
            output: "Here is my prompt:\n\nReview the essay below.",
            draft: "Here is my prompt:\n\nreview essay pls",
            expected: "Here is my prompt:\n\nReview the essay below."
        ),
        Case(
            label: "fence around a preface: both rules apply",
            output: "```\nHere is the prompt:\n\nWrite a haiku.\n```",
            expected: "Write a haiku.",
            unwrapsFence: true,
            stripsPreface: true
        ),
        Case(
            label: "preface before a fence: the preface goes, the fence stays (rules run in order)",
            output: "Here is the prompt:\n\n```\nWrite a haiku.\n```",
            expected: "```\nWrite a haiku.\n```",
            stripsPreface: true
        ),
    ]

    // MARK: - Things it must never do

    static let invariants: [Case] = [
        Case(label: "blank lines are not collapsed", output: "One\n\n\n\nTwo", expected: "One\n\n\n\nTwo"),
        Case(label: "quotes and dashes are not converted", output: "Say \"hi\" — or ‘hello’ -- or 'hey'.", expected: "Say \"hi\" — or ‘hello’ -- or 'hey'."),
        Case(label: "XML tags and brackets are kept", output: "<task>\nSummarise [paste text] for {{audience}} and $VAR or %s.\n</task>", expected: "<task>\nSummarise [paste text] for {{audience}} and $VAR or %s.\n</task>"),
        Case(label: "JSON is not parsed or unwrapped", output: "{\"prompt\": \"Write a haiku.\"}", expected: "{\"prompt\": \"Write a haiku.\"}"),
        Case(label: "inline backticks are kept", output: "Run `swift test` and report ```failures```.", expected: "Run `swift test` and report ```failures```."),
        Case(label: "interior indentation is kept", output: "Steps:\n    - indented\n\t- tabbed", expected: "Steps:\n    - indented\n\t- tabbed"),
    ]

    @Test(arguments: normalisation + fences + prefaces + invariants)
    func rules(_ testCase: Case) {
        let result = OutputPostProcessor.process(testCase.output, draft: testCase.draft)

        #expect(result.text == testCase.expected)
        #expect(result.didUnwrapFence == testCase.unwrapsFence)
        #expect(result.didStripPreface == testCase.stripsPreface)
        #expect(OutputPostProcessor.finalize(testCase.output, draft: testCase.draft) == testCase.expected)
    }

    @Test func longOutputIsNeverTruncated() {
        let long = (1...5_000).map { "Line \($0) of a very long prompt with ``` and <tags>." }.joined(separator: "\n")
        #expect(OutputPostProcessor.finalize(long, draft: "x") == long)
    }

    @Test func processingIsIdempotentForCleanOutputs() {
        for testCase in Self.invariants + Self.fences where !testCase.unwrapsFence {
            let once = OutputPostProcessor.finalize(testCase.output, draft: testCase.draft)
            #expect(OutputPostProcessor.finalize(once, draft: testCase.draft) == once, "\(testCase.label)")
        }
    }
}
