import Testing
@testable import PIDesign

struct ShortcutGlyphFormatterTests {
    @Test
    func modifiersUseAppleOrder() {
        let chord = KeyChord(.char("c"), [.command, .shift, .option, .control])
        #expect(ShortcutGlyphFormatter.caps(for: chord) == ["⌃", "⌥", "⇧", "⌘", "C"])
        #expect(ShortcutGlyphFormatter.string(for: chord) == "⌃⌥⇧⌘C")
    }

    @Test
    func namedKeysUseOneConsistentGlyph() {
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.escape)) == ["Esc"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.returnKey, .command)) == ["⌘", "↩"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.delete, .command)) == ["⌘", "⌫"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.pageDown)) == ["⇟"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.tab)) == ["⇥"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.tab, .shift)) == ["⇧", "⇥"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.char("\\"), .command)) == ["⌘", "\\"])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.char(","), .command)) == ["⌘", ","])
        #expect(ShortcutGlyphFormatter.caps(for: KeyChord(.char("["), .command)) == ["⌘", "["])
    }

    @Test
    func characterKeysAreStoredLowercasedAndShownUppercased() {
        #expect(KeyChord.Key.char("K") == .character("k"))
        #expect(ShortcutGlyphFormatter.keyGlyph(.char("k")) == "K")
    }
}
