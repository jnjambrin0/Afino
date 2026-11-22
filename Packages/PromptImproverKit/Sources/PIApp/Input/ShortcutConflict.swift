/// Why a key combination cannot become a shortcut. Recording stops, the field keeps what it had
/// and the user is told.
nonisolated enum ShortcutConflict: Equatable, Sendable {
    /// Another of Afino's shortcuts already has it; with that shortcut's name.
    case usedByShortcut(String)
    /// macOS has it, among the keyboard shortcuts turned on in System Settings.
    case usedBySystem
    /// An item of Afino's menus has it as its key equivalent; with the item's title.
    case usedByMenuItem(String)
}
