import Testing
@testable import PIPrompts

struct StreamingDisplayTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let accumulated: String
        let expected: String
        var draft = "make me a prompt"

        var testDescription: String { accumulated.debugDescription }
    }

    static let cases: [Case] = [
        // Leading whitespace
        Case(accumulated: "", expected: ""),
        Case(accumulated: " \n\t", expected: ""),
        Case(accumulated: "\n\n  Write a haiku", expected: "Write a haiku"),
        Case(accumulated: "Write\r\na haiku\r", expected: "Write\na haiku\n"),

        // A first line that may still become a wrapper opener is hidden
        Case(accumulated: "`", expected: ""),
        Case(accumulated: "``", expected: ""),
        Case(accumulated: "```", expected: ""),
        Case(accumulated: "```te", expected: ""),
        Case(accumulated: "```text", expected: ""),
        Case(accumulated: "```Prompt ", expected: ""),
        Case(accumulated: "  \n```p", expected: ""),

        // …and shown as soon as it cannot
        Case(accumulated: "`swift test` runs", expected: "`swift test` runs"),
        Case(accumulated: "``a", expected: "``a"),
        Case(accumulated: "```s", expected: "```s"),
        Case(accumulated: "```swift", expected: "```swift"),
        Case(accumulated: "```py\nprint(1)", expected: "```py\nprint(1)"),
        Case(accumulated: "```text more", expected: "```text more"),

        // A complete opener is hidden while the output may be wholly wrapped
        Case(accumulated: "```text\n", expected: ""),
        Case(accumulated: "```\nYou are", expected: "You are"),
        Case(accumulated: "\r\n```markdown\r\n\r\n# Task\r\nWrite", expected: "# Task\nWrite"),

        // …including a trailing line that may become its closer
        Case(accumulated: "```\nYou are a poet.\n`", expected: "You are a poet.\n"),
        Case(accumulated: "```\nYou are a poet.\n``", expected: "You are a poet.\n"),
        Case(accumulated: "```\nYou are a poet.\n```", expected: "You are a poet.\n"),
        Case(accumulated: "```\nYou are a poet.\n```\n\n", expected: "You are a poet.\n"),
        Case(accumulated: "````\nUse:\n```", expected: "Use:\n"),
        Case(accumulated: "````\nUse:\n```\n", expected: "Use:\n```\n"),

        // The wrapper is disproved: everything shows, opener included
        Case(accumulated: "```\nPart one\n```\nPart two", expected: "```\nPart one\n```\nPart two"),
        Case(accumulated: "```\nRefactor:\n```swift", expected: "```\nRefactor:\n```swift"),
        Case(accumulated: "```\nRefactor:\n```s", expected: "```\nRefactor:\n```s"),
        Case(accumulated: "```\nA\n````", expected: "```\nA\n````"),
        Case(accumulated: "````\nUse:\n```swift\nlet x = 1\n```\n", expected: "Use:\n```swift\nlet x = 1\n```\n"),

        // A draft that was wholly fenced never hides anything
        Case(accumulated: "```", expected: "```", draft: "```\nlog line\n```"),
        Case(accumulated: "```text\nSummarise", expected: "```text\nSummarise", draft: "```\nlog line\n```"),
    ]

    @Test(arguments: cases)
    func displayedText(_ testCase: Case) {
        let display = OutputPostProcessor.StreamingDisplay(draft: testCase.draft)
        #expect(display.text(for: testCase.accumulated) == testCase.expected)
    }

    /// Feeding a wrapped output one character at a time never shows the wrapper, and the final
    /// rules then unwrap it.
    @Test func wrappedOutputNeverShowsTheFenceWhileStreaming() {
        let output = "```text\nYou are a careful editor.\n\nKeep {{name}} as is.\n```\n"
        let display = OutputPostProcessor.StreamingDisplay(draft: "edit my text")
        var accumulated = ""
        for character in output {
            accumulated.append(character)
            let shown = display.text(for: accumulated)
            #expect(!shown.contains("```"), "showed a fence after \(accumulated.debugDescription)")
            #expect("You are a careful editor.\n\nKeep {{name}} as is.\n".hasPrefix(shown))
        }
        #expect(OutputPostProcessor.finalize(output, draft: "edit my text") == "You are a careful editor.\n\nKeep {{name}} as is.")
    }

    /// For an output that is not wrapped, what is shown only ever grows.
    @Test func unwrappedOutputGrowsMonotonically() {
        let output = "  Write a review of `main.swift`.\n\n```swift\nlet x = 1\n```\n\nBe brief."
        let display = OutputPostProcessor.StreamingDisplay(draft: "review")
        var accumulated = ""
        var previous = ""
        for character in output {
            accumulated.append(character)
            let shown = display.text(for: accumulated)
            #expect(shown.hasPrefix(previous), "display shrank after \(accumulated.debugDescription)")
            previous = shown
        }
        #expect(previous == "Write a review of `main.swift`.\n\n```swift\nlet x = 1\n```\n\nBe brief.")
    }

    /// A ```swift block is visible from its fourth character.
    @Test func languageFenceAppearsAsSoonAsItIsKnown() {
        let display = OutputPostProcessor.StreamingDisplay(draft: "x")
        #expect(display.text(for: "```") == "")
        #expect(display.text(for: "```s") == "```s")
    }
}
