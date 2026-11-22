/// The glyphs of a `KeyChord`. Hint bars, menus, buttons and Settings render chord caps through
/// it, so "Esc" and "esc", or "⏎" and "↩", cannot drift apart. Modifier order is Apple's:
/// ⌃ ⌥ ⇧ ⌘.
public nonisolated enum ShortcutGlyphFormatter {
    /// One glyph per modifier, in Apple's order.
    public static func modifierGlyphs(_ modifiers: KeyChord.Modifiers) -> [String] {
        var glyphs: [String] = []
        if modifiers.contains(.control) { glyphs.append("⌃") }
        if modifiers.contains(.option) { glyphs.append("⌥") }
        if modifiers.contains(.shift) { glyphs.append("⇧") }
        if modifiers.contains(.command) { glyphs.append("⌘") }
        return glyphs
    }

    /// The key's cap: an uppercased character, a symbol, or a short name ("Esc", "Space").
    public static func keyGlyph(_ key: KeyChord.Key) -> String {
        switch key {
        case .character(let value): value.uppercased()
        case .returnKey: "↩"
        case .escape: "Esc"
        case .delete: "⌫"
        case .tab: "⇥"
        case .space: "Space"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        }
    }

    /// One cap per modifier plus one for the key: `["⇧", "⌘", "C"]`.
    public static func caps(for chord: KeyChord) -> [String] {
        modifierGlyphs(chord.modifiers) + [keyGlyph(chord.key)]
    }

    /// Compact inline form: `"⇧⌘C"`.
    public static func string(for chord: KeyChord) -> String {
        caps(for: chord).joined()
    }
}
