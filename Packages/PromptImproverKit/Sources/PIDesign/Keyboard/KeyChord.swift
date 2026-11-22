import AppKit
import Carbon.HIToolbox

/// A key plus modifiers as a plain value, so key maps, menus, hint bars and
/// Settings describe shortcuts without AppKit event types.
public nonisolated struct KeyChord: Hashable, Sendable {
    /// ⌃ ⌥ ⇧ ⌘, the only modifiers a chord records.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Keeps ⌃⌥⇧⌘ and drops everything else (Caps Lock, Fn, keypad).
        public init(_ flags: NSEvent.ModifierFlags) {
            var modifiers: Modifiers = []
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            self = modifiers
        }

        /// The same modifiers as AppKit event flags.
        public var eventModifierFlags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.control) { flags.insert(.control) }
            if contains(.option) { flags.insert(.option) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.command) { flags.insert(.command) }
            return flags
        }
    }

    /// A printable character or one of the named keys the app binds.
    public enum Key: Hashable, Sendable {
        /// A printable key, stored lowercased (`"k"`, `"1"`, `","`, `"\\"`, `"["`).
        case character(String)
        case returnKey
        case escape
        case delete
        case tab
        case space
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case pageUp
        case pageDown

        /// A printable key; the character is lowercased.
        public static func char(_ value: String) -> Key {
            .character(value.lowercased())
        }
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The `NSMenuItem.keyEquivalent` string for this chord.
    public var menuKeyEquivalent: String {
        switch key {
        case .character(let value): value
        case .returnKey: "\r"
        case .escape: "\u{1b}"
        case .delete: "\u{8}"
        case .tab: "\t"
        case .space: " "
        case .upArrow: Self.functionKey(NSUpArrowFunctionKey)
        case .downArrow: Self.functionKey(NSDownArrowFunctionKey)
        case .leftArrow: Self.functionKey(NSLeftArrowFunctionKey)
        case .rightArrow: Self.functionKey(NSRightArrowFunctionKey)
        case .pageUp: Self.functionKey(NSPageUpFunctionKey)
        case .pageDown: Self.functionKey(NSPageDownFunctionKey)
        }
    }

    private static func functionKey(_ value: Int) -> String {
        UnicodeScalar(UInt32(value)).map { String(Character($0)) } ?? ""
    }
}

public nonisolated extension KeyChord {
    /// Bridges a key event to a chord. Named keys come from the hardware key
    /// code; printable keys from `charactersIgnoringModifiers` (lowercased, so
    /// ⇧ is read from `modifiers`, not from the character). Returns `nil` for
    /// keys a chord cannot describe (function keys, bare modifiers).
    init?(keyCode: UInt16, charactersIgnoringModifiers: String?, modifierFlags: NSEvent.ModifierFlags) {
        let modifiers = Modifiers(modifierFlags)
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: self.init(.returnKey, modifiers)
        case kVK_Escape: self.init(.escape, modifiers)
        case kVK_Delete: self.init(.delete, modifiers)
        case kVK_Tab: self.init(.tab, modifiers)
        case kVK_Space: self.init(.space, modifiers)
        case kVK_UpArrow: self.init(.upArrow, modifiers)
        case kVK_DownArrow: self.init(.downArrow, modifiers)
        case kVK_LeftArrow: self.init(.leftArrow, modifiers)
        case kVK_RightArrow: self.init(.rightArrow, modifiers)
        case kVK_PageUp: self.init(.pageUp, modifiers)
        case kVK_PageDown: self.init(.pageDown, modifiers)
        default:
            guard let character = charactersIgnoringModifiers?.lowercased().first,
                  !character.isNewline,
                  character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0xF700 }) else {
                return nil
            }
            self.init(.character(String(character)), modifiers)
        }
    }

    /// The chord of a key-down event; `nil` for any other event type.
    init?(event: NSEvent) {
        guard event.type == .keyDown else {
            return nil
        }
        self.init(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }
}
