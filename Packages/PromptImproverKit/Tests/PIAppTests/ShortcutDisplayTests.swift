import AppKit
import Carbon.HIToolbox
@testable import PIApp
import Testing

/// How a shortcut is written out.
struct ShortcutDisplayTests {
    /// A layout where key 35 types "p" and key 9 types "v", as on ANSI.
    private func layout(_ keyCode: Int) -> Character? {
        switch keyCode {
        case kVK_ANSI_P: "p"
        case kVK_ANSI_V: "v"
        default: nil
        }
    }

    private func display(_ shortcut: Shortcut) -> String {
        ShortcutDisplay.string(for: shortcut, spaceKeyName: "Space", layoutCharacter: layout)
    }

    @Test func modifiersComeInTheOrderMenusUse() {
        #expect(ShortcutDisplay.modifierGlyphs([.command, .shift, .option, .control]) == "⌃⌥⇧⌘")
        #expect(ShortcutDisplay.modifierGlyphs([.capsLock, .function]) == "")
    }

    @Test func aLetterIsShownInUppercaseAsTheLayoutTypesIt() {
        #expect(display(Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .shift])) == "⇧⌘V")
        #expect(display(ActivationShortcutDefaults.primary) == "⌃⌥P")
        #expect(display(ActivationShortcutDefaults.fallback) == "⌃⌥⌘P")
    }

    @Test func theSpaceBarIsCalledByItsName() {
        #expect(display(Shortcut(keyCode: kVK_Space, modifiers: .control)) == "⌃Space")
    }

    @Test(arguments: [
        (kVK_RightArrow, "⌘→"), (kVK_LeftArrow, "⌘←"), (kVK_Return, "⌘↩"), (kVK_Delete, "⌘⌫"),
        (kVK_F1, "⌘F1"), (kVK_F12, "⌘F12"), (kVK_F20, "⌘F20"), (kVK_Help, "⌘?⃝"),
        (kVK_ANSI_KeypadClear, "⌘⌧"), (kVK_ANSI_KeypadEnter, "⌘⌅"), (kVK_ANSI_Keypad7, "⌘7"), (kVK_ANSI_KeypadMultiply, "⌘*"),
    ])
    func keysWithoutACharacterOfTheLayoutHaveAFixedName(keyCode: Int, expected: String) {
        #expect(display(Shortcut(keyCode: keyCode, modifiers: .command)) == expected)
    }

    @Test func aKeyTheLayoutCannotNameShowsItsCode() {
        #expect(display(Shortcut(keyCode: 200, modifiers: .control)) == "⌃#200")
    }
}
