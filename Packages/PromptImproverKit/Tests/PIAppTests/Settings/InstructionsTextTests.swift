import Foundation
@testable import PIApp
import Testing

/// The custom instructions editor: the counter and the 2,000-character cap.
struct InstructionsTextTests {
    @Test func theLimitIsTheEnginesLimit() {
        #expect(InstructionsText.limit == 2_000)
    }

    @Test func theCounterTurnsOrangeAtNinetyPercent() {
        #expect(!InstructionsText.count(of: String(repeating: "a", count: 1_799)).isNearLimit)
        #expect(InstructionsText.count(of: String(repeating: "a", count: 1_800)).isNearLimit)
        #expect(InstructionsText.count(of: "").used == 0)
    }

    @Test func theCounterCountsCharactersAsTheEngineDoes() {
        // One family emoji is one character, however many code units it takes.
        let count = InstructionsText.count(of: "Hi 👨‍👩‍👧")
        #expect(count.used == 4)
        #expect(count.limit == 2_000)
    }

    @Test func theCounterReadsUsedOverLimit() {
        let text = InstructionsText.count(of: String(repeating: "a", count: 212)).text
        #expect(text.hasPrefix("212 / 2"))
        #expect(text.hasSuffix("000"))
    }

    @Test func typingStopsAtTheLimit() {
        let full = String(repeating: "a", count: 2_000)
        #expect(InstructionsText.allowedReplacement(in: full, range: NSRange(location: 2_000, length: 0), replacement: "b") == nil)

        let almost = String(repeating: "a", count: 1_999)
        #expect(InstructionsText.allowedReplacement(in: almost, range: NSRange(location: 1_999, length: 0), replacement: "b") == "b")
    }

    @Test func aPasteIsCutToWhatFits() {
        let text = String(repeating: "a", count: 1_995)
        let allowed = InstructionsText.allowedReplacement(
            in: text, range: NSRange(location: 1_995, length: 0), replacement: "0123456789")
        #expect(allowed == "01234")
    }

    @Test func replacingSelectedTextFreesItsRoom() {
        let full = String(repeating: "a", count: 2_000)
        let allowed = InstructionsText.allowedReplacement(in: full, range: NSRange(location: 0, length: 10), replacement: "0123456789AB")
        #expect(allowed == "0123456789")
        // Deleting is always allowed.
        #expect(InstructionsText.allowedReplacement(in: full, range: NSRange(location: 0, length: 5), replacement: "") == "")
    }

    @Test func aCutNeverSplitsACharacter() {
        let text = String(repeating: "a", count: 1_999)
        let allowed = InstructionsText.allowedReplacement(
            in: text, range: NSRange(location: (text as NSString).length, length: 0), replacement: "👨‍👩‍👧x")
        #expect(allowed == "👨‍👩‍👧")
    }

    @Test func anExampleGoesOnANewLine() {
        #expect(InstructionsText.appending("Use XML tags", to: "") == "Use XML tags")
        #expect(InstructionsText.appending("Use XML tags", to: "  \n") == "Use XML tags")
        #expect(InstructionsText.appending("Use XML tags", to: "Be brief.") == "Be brief.\nUse XML tags")
        #expect(InstructionsText.appending("Use XML tags", to: "Be brief.\n") == "Be brief.\nUse XML tags")
    }

    @Test func anExampleIsNotAddedTwiceOrPastTheLimit() {
        #expect(InstructionsText.appending("Use XML tags", to: "Be brief.\nUse XML tags") == nil)
        let nearlyFull = String(repeating: "a", count: 1_990)
        #expect(InstructionsText.appending("Use XML tags", to: nearlyFull) == nil)
    }

    @Test func textFromElsewhereIsCapped() {
        #expect(InstructionsText.capped(String(repeating: "a", count: 2_500)).count == 2_000)
        #expect(InstructionsText.capped("short") == "short")
    }

    @Test func theExamplesAreTheFourOffered() {
        #expect(InstructionsText.Example.allCases.count == 4)
        #expect(InstructionsText.Example.allCases.allSatisfy { !$0.sentence.hasPrefix("settings.") })
    }
}
