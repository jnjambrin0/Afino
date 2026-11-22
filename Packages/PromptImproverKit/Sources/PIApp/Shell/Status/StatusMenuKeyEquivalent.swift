import AppKit

/// Turns a shortcut shown as caps (["⌃", "⌥", "P"]) into a menu item's key equivalent, so the
/// system menu draws it in its own style.
enum StatusMenuKeyEquivalent {
    private static let modifiers: [String: NSEvent.ModifierFlags] = [
        "⌘": .command, "⌥": .option, "⌃": .control, "⇧": .shift,
    ]

    /// The key and modifiers for `caps`, or nil when the last cap is not a single character
    /// (a named key such as Space is left out rather than shown wrong).
    static func parse(caps: [String]) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let last = caps.last, last.count == 1, modifiers[last] == nil else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for cap in caps.dropLast() {
            guard let flag = modifiers[cap] else { return nil }
            flags.insert(flag)
        }
        return (last.lowercased(), flags)
    }

    /// Gives `item` the key equivalent `caps` stand for; leaves it without one when they cannot
    /// be parsed.
    static func apply(caps: [String], to item: NSMenuItem) {
        guard let parsed = parse(caps: caps) else { return }
        item.keyEquivalent = parsed.key
        item.keyEquivalentModifierMask = parsed.modifiers
    }
}
