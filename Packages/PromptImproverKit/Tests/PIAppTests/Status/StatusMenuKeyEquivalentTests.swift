import AppKit
@testable import PIApp
import Testing

/// Key caps turned into the menu bar menu's key equivalents.
struct StatusMenuKeyEquivalentTests {
    @Test
    func capsBecomeAKeyEquivalent() {
        let parsed = StatusMenuKeyEquivalent.parse(caps: ["⌃", "⌥", "P"])
        #expect(parsed?.key == "p")
        #expect(parsed?.modifiers == [.control, .option])
        #expect(StatusMenuKeyEquivalent.parse(caps: ["⌘", ","])?.key == ",")
    }

    @Test
    func namedKeysAndUnknownCapsAreLeftOut() {
        #expect(StatusMenuKeyEquivalent.parse(caps: ["⌥", "Space"]) == nil)
        #expect(StatusMenuKeyEquivalent.parse(caps: ["fn", "P"]) == nil)
        #expect(StatusMenuKeyEquivalent.parse(caps: ["⌘"]) == nil)
        #expect(StatusMenuKeyEquivalent.parse(caps: []) == nil)
    }
}
