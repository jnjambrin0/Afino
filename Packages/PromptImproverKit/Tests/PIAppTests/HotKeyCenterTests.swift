import AppKit
@testable import PIApp
import Testing

/// A damaged shortcut never takes the app down, and a shortcut keeps only the modifiers a hot key
/// can use.
struct HotKeyCenterTests {
    @Test func aKeyCodeNoKeyHasIsRefusedWithoutStoppingTheApp() {
        let center = HotKeyCenter()

        #expect(!center.register(Shortcut(keyCode: Int(UInt32.max) + 1, modifiers: .command), caller: "test") {})
        #expect(!center.register(Shortcut(keyCode: -1, modifiers: .command), caller: "test") {})
        #expect(!center.isAvailable(Shortcut(keyCode: -1, modifiers: .command)))
        center.unregister(caller: "test")
    }

    @Test func aStoredShortcutWithAKeyCodeOutOfRangeDoesNotDecode() {
        let damaged = Data(#"{"keyCode":70000,"internalModifiers":786432}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Shortcut.self, from: damaged)
        }
    }

    @Test func aShortcutKeepsOnlyCommandOptionControlAndShift() {
        let shortcut = Shortcut(keyCode: 35, modifiers: [.control, .option, .capsLock, .function, .numericPad])

        #expect(shortcut.modifiers == [.control, .option])
    }
}
