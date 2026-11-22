import AppKit
import Carbon.HIToolbox
import Testing
@testable import PIDesign

struct KeyChordTests {
    @Test
    func namedKeysComeFromTheKeyCode() {
        let cases: [(Int, KeyChord.Key)] = [
            (kVK_Return, .returnKey), (kVK_ANSI_KeypadEnter, .returnKey), (kVK_Escape, .escape),
            (kVK_Delete, .delete), (kVK_Tab, .tab), (kVK_Space, .space), (kVK_UpArrow, .upArrow),
            (kVK_DownArrow, .downArrow), (kVK_LeftArrow, .leftArrow), (kVK_RightArrow, .rightArrow),
            (kVK_PageUp, .pageUp), (kVK_PageDown, .pageDown),
        ]
        for (code, key) in cases {
            let chord = KeyChord(keyCode: UInt16(code), charactersIgnoringModifiers: "x", modifierFlags: .command)
            #expect(chord == KeyChord(key, .command))
        }
    }

    @Test
    func printableKeysAreLowercasedAndKeepShiftAsAModifier() {
        let chord = KeyChord(keyCode: UInt16(kVK_ANSI_K), charactersIgnoringModifiers: "K", modifierFlags: [.command, .shift])
        #expect(chord == KeyChord(.char("k"), [.command, .shift]))
        let bracket = KeyChord(keyCode: UInt16(kVK_ANSI_LeftBracket), charactersIgnoringModifiers: "[", modifierFlags: .command)
        #expect(bracket == KeyChord(.char("["), .command))
    }

    @Test
    func keysAChordCannotDescribeAreNil() {
        let functionKey = String(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!))
        #expect(KeyChord(keyCode: UInt16(kVK_F5), charactersIgnoringModifiers: functionKey, modifierFlags: []) == nil)
        #expect(KeyChord(keyCode: UInt16(kVK_ANSI_A), charactersIgnoringModifiers: nil, modifierFlags: []) == nil)
        #expect(KeyChord(keyCode: UInt16(kVK_ANSI_A), charactersIgnoringModifiers: "\n", modifierFlags: []) == nil)
    }

    @Test
    func keyDownEventsBridgeAndOtherEventsDoNot() throws {
        let keyDown = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_K)
        ))
        #expect(KeyChord(event: keyDown) == KeyChord(.char("k"), .command))

        let keyUp = try #require(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_K)
        ))
        #expect(KeyChord(event: keyUp) == nil)
    }

    @Test
    func modifiersRoundTripThroughEventFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .numericPad]
        let modifiers = KeyChord.Modifiers(flags)
        #expect(modifiers == [.command, .shift])
        #expect(modifiers.eventModifierFlags == [.command, .shift])
    }

    @Test
    func menuKeyEquivalents() {
        #expect(KeyChord(.char("n"), .command).menuKeyEquivalent == "n")
        #expect(KeyChord(.returnKey).menuKeyEquivalent == "\r")
        #expect(KeyChord(.escape).menuKeyEquivalent == "\u{1b}")
        #expect(KeyChord(.tab).menuKeyEquivalent == "\t")
        #expect(KeyChord(.space).menuKeyEquivalent == " ")
        #expect(KeyChord(.upArrow).menuKeyEquivalent == String(Character(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)))
        #expect(KeyChord(.pageDown).menuKeyEquivalent == String(Character(UnicodeScalar(UInt32(NSPageDownFunctionKey))!)))
    }

    @Test
    func chordsAreValues() {
        let set: Set<KeyChord> = [KeyChord(.char("K"), .command), KeyChord(.char("k"), .command)]
        #expect(set.count == 1)
        #expect(KeyChord(.char("k"), .command) != KeyChord(.char("k"), [.command, .shift]))
    }
}
