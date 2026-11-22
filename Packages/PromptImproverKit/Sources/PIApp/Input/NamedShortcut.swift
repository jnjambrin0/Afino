/// A shortcut together with what it does, as the user knows it: the name a conflict reports.
nonisolated struct NamedShortcut: Equatable, Sendable {
    let name: String
    let shortcut: Shortcut

    init(name: String, shortcut: Shortcut) {
        self.name = name
        self.shortcut = shortcut
    }
}
