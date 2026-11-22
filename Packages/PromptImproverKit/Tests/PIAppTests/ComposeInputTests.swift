import AppKit
import Carbon.HIToolbox
@testable import PIApp
import PIDesign
import Testing

/// The compose input: what Return does, and how tall the input wants to be.
struct ComposeInputTests {
    // MARK: Return

    @Test func returnSubmits() {
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: [], hasMarkedText: false) == .submit)
        #expect(ComposeReturnAction.action(keyCode: kVK_ANSI_KeypadEnter, modifiers: [], hasMarkedText: false) == .submit)
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: .command, hasMarkedText: false) == .submit)
    }

    @Test func shiftReturnAndOptionReturnStartANewLine() {
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: .shift, hasMarkedText: false) == .newline)
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: .option, hasMarkedText: false) == .newline)
    }

    @Test func returnWhileAnInputMethodComposesNeverSubmits() {
        for modifiers: NSEvent.ModifierFlags in [[], .command, .shift, .option] {
            #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: modifiers, hasMarkedText: true) == .passThrough)
        }
    }

    @Test func capsLockAndTheFunctionBitDoNotChangeReturn() {
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: [.capsLock, .function], hasMarkedText: false) == .submit)
    }

    @Test func otherKeysAndCombinationsGoToTheTextSystem() {
        #expect(ComposeReturnAction.action(keyCode: kVK_ANSI_A, modifiers: [], hasMarkedText: false) == .passThrough)
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: .control, hasMarkedText: false) == .passThrough)
        #expect(ComposeReturnAction.action(keyCode: kVK_Return, modifiers: [.shift, .command], hasMarkedText: false) == .passThrough)
    }

    // MARK: Height

    private func makeInput() -> ComposeInputView {
        let input = ComposeInputView(placeholder: "Describe what you want, or paste a prompt…")
        input.frame = NSRect(x: 0, y: 0, width: EmberDesign.Panel.width - 2 * EmberDesign.Panel.contentInset, height: EmberDesign.Panel.inputMinHeight)
        input.layoutSubtreeIfNeeded()
        return input
    }

    private func type(_ text: String, into input: ComposeInputView) {
        input.textView.insertText(text, replacementRange: input.textView.selectedRange())
    }

    @Test func theTextViewIsOnTextKit2() {
        let input = makeInput()

        #expect(input.textView.textLayoutManager != nil)
        #expect(!input.textView.isRichText)
        #expect(!input.textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!input.textView.isAutomaticDashSubstitutionEnabled)
        #expect(!input.textView.isAutomaticTextReplacementEnabled)
        #expect(!input.textView.isContinuousSpellCheckingEnabled)
        #expect(input.textView.writingToolsBehavior == .default)
    }

    @Test func anEmptyOrOneLineInputIs52PointsTall() {
        let input = makeInput()
        #expect(input.preferredHeight == EmberDesign.Panel.inputMinHeight)

        type("Write a haiku about latency", into: input)
        #expect(input.preferredHeight == EmberDesign.Panel.inputMinHeight)
    }

    @Test func eachLineAddsOneLineHeight() {
        let input = makeInput()
        var heights: [CGFloat] = []
        input.onPreferredHeightChange = { _, new in heights.append(new) }

        type("one", into: input)
        type("\ntwo", into: input)
        type("\nthree", into: input)

        let line = input.oneLineHeight
        #expect(heights.count == 2)
        #expect(abs(heights[0] - (EmberDesign.Panel.inputMinHeight + line)) <= 1)
        #expect(abs(heights[1] - (EmberDesign.Panel.inputMinHeight + 2 * line)) <= 1)
    }

    @Test func aTrailingNewlineCountsAsALine() {
        let input = makeInput()

        type("one\n", into: input)

        #expect(abs(input.preferredHeight - (EmberDesign.Panel.inputMinHeight + input.oneLineHeight)) <= 1)
    }

    @Test func theInputStopsGrowingAtTenLines() {
        let input = makeInput()

        type(Array(repeating: "line", count: 40).joined(separator: "\n"), into: input)
        let tenLines = input.preferredHeight

        #expect(abs(tenLines - (EmberDesign.Panel.inputMinHeight + 9 * input.oneLineHeight)) <= 1)
        type("\nmore", into: input)
        #expect(input.preferredHeight == tenLines)
    }

    @Test func aLongLineWrapsAndGrows() {
        let input = makeInput()

        type(String(repeating: "wrap me ", count: 40), into: input)

        #expect(input.preferredHeight > EmberDesign.Panel.inputMinHeight + input.oneLineHeight)
    }

    @Test func eachLineIsTwentyPointsAsTheGeometrySays() {
        let input = makeInput()

        type("one\ntwo\nthree", into: input)

        // 32 + 20 × 3 = 92, the compose geometry's input for three lines.
        #expect(input.oneLineHeight == EmberDesign.Panel.inputLineHeight)
        #expect(input.preferredHeight == EmberDesign.Panel.inputHeight(forLines: 3))
    }

    @Test func setDraftShowsTheSessionsTextWithoutReportingItBack() {
        let input = makeInput()
        var reported: [String] = []
        input.onDraftChange = { reported.append($0) }

        input.setDraft("Recalled draft\nwith two lines")

        #expect(input.draft == "Recalled draft\nwith two lines")
        #expect(input.preferredHeight == EmberDesign.Panel.inputHeight(forLines: 2))
        #expect(input.textView.selectedRange().location == ("Recalled draft\nwith two lines" as NSString).length)
        #expect(reported.isEmpty)
    }

    @Test func typingReportsTheDraft() {
        let input = makeInput()
        var reported: [String] = []
        input.onDraftChange = { reported.append($0) }

        type("Hi", into: input)

        #expect(reported.last == "Hi")
    }

    @Test func returnSubmitsTheDraftAsItIs() {
        let input = makeInput()
        var submitted: [String] = []
        input.onSubmit = { submitted.append($0) }
        type("Explain TextKit 2", into: input)

        input.textView.onSubmit?()

        #expect(submitted == ["Explain TextKit 2"])
        #expect(input.draft == "Explain TextKit 2")
    }
}
