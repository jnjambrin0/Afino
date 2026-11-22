import PIDesign

/// One piece of a row's keys as drawn: a key cap, words the user types first, or the mark
/// between two keys that share their modifiers.
nonisolated enum WelcomeKeyToken: Hashable, Sendable {
    /// One key cap, with its glyph or name.
    case cap(String)
    /// Something typed first ("shorter"), drawn in quotes.
    case typed(String)
    /// Between the two ends of a range: ⌘ 1 – 4.
    case through
    /// Between two keys that go together: ⌘ [ / ].
    case or
}

/// One shortcut of the keyboard step: its keys and a few words. Every chord is read from
/// `PanelKeyMap`, so the welcome cannot show a key the panel does not answer to.
nonisolated struct WelcomeKeyRow: Identifiable, Equatable, Sendable {
    enum Keys: Equatable, Sendable {
        case chord(KeyChord)
        /// Type `sample`, then press the chord ("shorter" ↩ refines).
        case typed(sample: String, then: KeyChord)
        /// Every chord from the first to the last (⌘1 to ⌘4).
        case range(KeyChord, KeyChord)
        /// Two chords that go together (⌘[ and ⌘]).
        case pair(KeyChord, KeyChord)
    }

    let id: String
    let label: String
    /// A short qualifier after the label, quieter ("in an empty field").
    var note: String?
    let keys: Keys

    /// Every chord the row shows.
    var chords: [KeyChord] {
        switch keys {
        case .chord(let chord), .typed(_, let chord): [chord]
        case .range(let first, let last), .pair(let first, let last): [first, last]
        }
    }

    /// The caps as drawn. Two chords with the same modifiers show them once: ⌘ 1 – 4, ⌘ [ / ].
    var tokens: [WelcomeKeyToken] {
        func caps(_ chord: KeyChord) -> [WelcomeKeyToken] {
            ShortcutGlyphFormatter.caps(for: chord).map(WelcomeKeyToken.cap)
        }
        func joined(_ first: KeyChord, _ last: KeyChord, by mark: WelcomeKeyToken) -> [WelcomeKeyToken] {
            guard first.modifiers == last.modifiers else { return caps(first) + [mark] + caps(last) }
            let modifiers = ShortcutGlyphFormatter.modifierGlyphs(first.modifiers).map(WelcomeKeyToken.cap)
            return modifiers + [.cap(ShortcutGlyphFormatter.keyGlyph(first.key)), mark, .cap(ShortcutGlyphFormatter.keyGlyph(last.key))]
        }
        switch keys {
        case .chord(let chord): return caps(chord)
        case .typed(let sample, let chord): return [.typed(sample)] + caps(chord)
        case .range(let first, let last): return joined(first, last, by: .through)
        case .pair(let first, let last): return joined(first, last, by: .or)
        }
    }

    /// The keys in words, for VoiceOver ("Command 1 to Command 4").
    var spokenKeys: String {
        switch keys {
        case .chord(let chord):
            return WelcomeSpokenKeys.words(for: chord)
        case .typed(let sample, let chord):
            return OnboardingStrings.text("welcome.spoken.typed", sample, WelcomeSpokenKeys.words(for: chord))
        case .range(let first, let last):
            return OnboardingStrings.text("welcome.spoken.range", WelcomeSpokenKeys.words(for: first), WelcomeSpokenKeys.words(for: last))
        case .pair(let first, let last):
            return OnboardingStrings.text("welcome.spoken.pair", WelcomeSpokenKeys.words(for: first), WelcomeSpokenKeys.words(for: last))
        }
    }

    /// What VoiceOver says for the whole row: "Improve: Return".
    var spoken: String {
        let label = note.map { "\(self.label) \($0)" } ?? self.label
        return OnboardingStrings.text("welcome.spoken.row", label, spokenKeys)
    }
}

/// A titled group of rows on the keyboard step.
nonisolated struct WelcomeKeyGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [WelcomeKeyRow]
}

/// The keyboard step's three groups (Write, Result, Anytime), built from the panel's key map.
nonisolated enum WelcomeKeyGuide {
    /// - Parameter targetCount: How many targets ⌘1… can pick (the packs the app ships).
    static func groups(targetCount: Int) -> [WelcomeKeyGroup] {
        func chord(_ command: PanelCommand, _ screen: PanelScreen) -> KeyChord? {
            PanelKeyMap.chord(for: command, in: screen)
        }
        func row(_ id: String, _ label: String, note: String? = nil, _ keys: WelcomeKeyRow.Keys?) -> WelcomeKeyRow? {
            keys.map { WelcomeKeyRow(id: id, label: label, note: note, keys: $0) }
        }
        func single(_ command: PanelCommand, _ screen: PanelScreen) -> WelcomeKeyRow.Keys? {
            chord(command, screen).map(WelcomeKeyRow.Keys.chord)
        }

        let lastTarget = max(min(targetCount, PanelKeyMap.targetChords.count), 1) - 1
        let pickTarget: WelcomeKeyRow.Keys? = {
            guard let first = chord(.selectTarget(0), .compose) else { return nil }
            guard lastTarget > 0, let last = chord(.selectTarget(lastTarget), .compose) else { return .chord(first) }
            return .range(first, last)
        }()
        let refine: WelcomeKeyRow.Keys? = chord(.primary, .result).map {
            .typed(sample: OnboardingStrings.text("welcome.keys.refine.sample"), then: $0)
        }
        let versions: WelcomeKeyRow.Keys? = {
            guard let previous = chord(.previousVersion, .result), let next = chord(.nextVersion, .result) else { return nil }
            return .pair(previous, next)
        }()

        let write = [
            row("improve", OnboardingStrings.text("welcome.keys.improve"), single(.primary, .compose)),
            row("newLine", OnboardingStrings.text("welcome.keys.newLine"), single(.insertNewline, .compose)),
            row("nextTarget", OnboardingStrings.text("welcome.keys.nextTarget"), single(.nextTarget, .compose)),
            row("pickTarget", OnboardingStrings.text("welcome.keys.pickTarget"), pickTarget),
        ]
        let result = [
            row("copyClose", OnboardingStrings.text("welcome.keys.copyClose"), single(.primary, .result)),
            row("refine", OnboardingStrings.text("welcome.keys.refine"), refine),
            row("regenerate", OnboardingStrings.text("welcome.keys.regenerate"), single(.regenerate, .result)),
            row("versions", OnboardingStrings.text("welcome.keys.versions"), versions),
        ]
        let anywhere = [
            row("actions", OnboardingStrings.text("welcome.keys.actions"), single(.toggleActions, .compose)),
            row("history", OnboardingStrings.text("welcome.keys.history"), single(.toggleHistory, .compose)),
            row("lastDraft", OnboardingStrings.text("welcome.keys.lastDraft"),
                note: OnboardingStrings.text("welcome.keys.lastDraft.note"), single(.recallOlder, .compose)),
            row("close", OnboardingStrings.text("welcome.keys.close"),
                note: OnboardingStrings.text("welcome.keys.close.note"), single(.escape, .compose)),
        ]
        return [
            WelcomeKeyGroup(id: "write", title: OnboardingStrings.text("welcome.keys.group.write"), rows: write.compactMap { $0 }),
            WelcomeKeyGroup(id: "result", title: OnboardingStrings.text("welcome.keys.group.result"), rows: result.compactMap { $0 }),
            WelcomeKeyGroup(id: "anywhere", title: OnboardingStrings.text("welcome.keys.group.anywhere"), rows: anywhere.compactMap { $0 }),
        ]
    }
}
