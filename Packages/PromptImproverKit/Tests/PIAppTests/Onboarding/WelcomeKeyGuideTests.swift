import Foundation
@testable import PIApp
import PIDesign
import Testing

/// The keyboard step can never show a key the panel does not answer to: every chord it shows is
/// the one `PanelKeyMap` has for the command the row describes, and every one draws as caps.
struct WelcomeKeyGuideTests {
    private static let targetCount = 4
    private static let groups = WelcomeKeyGuide.groups(targetCount: targetCount)

    /// What each row says it does, as panel commands on the screen where they work.
    private static let documented: [String: [(PanelCommand, PanelScreen)]] = [
        "improve": [(.primary, .compose)],
        "newLine": [(.insertNewline, .compose)],
        "nextTarget": [(.nextTarget, .compose)],
        "pickTarget": [(.selectTarget(0), .compose), (.selectTarget(targetCount - 1), .compose)],
        "copyClose": [(.primary, .result)],
        "refine": [(.primary, .result)],
        "regenerate": [(.regenerate, .result)],
        "versions": [(.previousVersion, .result), (.nextVersion, .result)],
        "actions": [(.toggleActions, .compose)],
        "history": [(.toggleHistory, .compose)],
        "lastDraft": [(.recallOlder, .compose)],
        "close": [(.escape, .compose)],
    ]

    private static var rows: [WelcomeKeyRow] { groups.flatMap(\.rows) }

    @Test func threeGroupsOfFourInReadingOrder() {
        #expect(Self.groups.map(\.id) == ["write", "result", "anywhere"])
        #expect(Self.groups.map(\.rows.count) == [4, 4, 4])
        #expect(Self.rows.map(\.id) == [
            "improve", "newLine", "nextTarget", "pickTarget",
            "copyClose", "refine", "regenerate", "versions",
            "actions", "history", "lastDraft", "close",
        ])
        for group in Self.groups {
            #expect(!group.title.isEmpty)
        }
    }

    @Test func everyChordShownIsThePanelKeyMapsOwn() throws {
        for row in Self.rows {
            let sources = try #require(Self.documented[row.id], "\(row.id) is not documented")
            let expected = try sources.map { command, screen in
                try #require(PanelKeyMap.chord(for: command, in: screen), "\(command) has no key on \(screen)")
            }
            #expect(row.chords == expected, "\(row.id)")
            // And the panel answers to it there.
            for ((command, screen), chord) in zip(sources, row.chords) {
                #expect(PanelKeyMap.bindings(in: screen).contains { $0.chord == chord && $0.command == command }, "\(row.id)")
            }
        }
    }

    @Test func everyChordDrawsAsCapsAndEveryRowHasWords() {
        for row in Self.rows {
            #expect(!row.label.isEmpty, "\(row.id)")
            #expect(!row.tokens.isEmpty, "\(row.id)")
            for chord in row.chords {
                #expect(!ShortcutGlyphFormatter.string(for: chord).isEmpty, "\(row.id)")
            }
            for case .cap(let glyph) in row.tokens {
                #expect(!glyph.isEmpty, "\(row.id)")
            }
            #expect(!row.spokenKeys.isEmpty, "\(row.id)")
            #expect(row.spoken.contains(row.label), "\(row.id)")
        }
    }

    @Test func eachRowShowsTheKeysItDocuments() {
        func caps(_ id: String) -> [WelcomeKeyToken] {
            Self.rows.first { $0.id == id }?.tokens ?? []
        }
        #expect(caps("improve") == [.cap("↩")])
        #expect(caps("newLine") == [.cap("⇧"), .cap("↩")])
        #expect(caps("nextTarget") == [.cap("⇥")])
        // Shared modifiers are shown once: ⌘ 1 – 4, ⌘ [ / ].
        #expect(caps("pickTarget") == [.cap("⌘"), .cap("1"), .through, .cap("4")])
        #expect(caps("copyClose") == [.cap("↩")])
        #expect(caps("refine") == [.typed(OnboardingStrings.text("welcome.keys.refine.sample")), .cap("↩")])
        #expect(caps("regenerate") == [.cap("⌘"), .cap("R")])
        #expect(caps("versions") == [.cap("⌘"), .cap("["), .or, .cap("]")])
        #expect(caps("actions") == [.cap("⌘"), .cap("K")])
        #expect(caps("history") == [.cap("⌘"), .cap("Y")])
        #expect(caps("lastDraft") == [.cap("↑")])
        #expect(caps("close") == [.cap("Esc")])
    }

    @Test func pickingATargetFollowsHowManyTargetsThereAre() {
        func pick(_ count: Int) -> WelcomeKeyRow? {
            WelcomeKeyGuide.groups(targetCount: count).flatMap(\.rows).first { $0.id == "pickTarget" }
        }
        #expect(pick(1)?.chords == [KeyChord(.char("1"), .command)])
        #expect(pick(3)?.chords.last == KeyChord(.char("3"), .command))
        // Never beyond ⌘9.
        #expect(pick(12)?.chords.last == KeyChord(.char("9"), .command))
    }

    @Test func chordsWithDifferentModifiersKeepTheirOwnCaps() {
        let row = WelcomeKeyRow(id: "x", label: "x", keys: .pair(KeyChord(.tab), KeyChord(.tab, .shift)))
        #expect(row.tokens == [.cap("⇥"), .or, .cap("⇧"), .cap("⇥")])
    }

    @Test func rowsAreSpokenAsWords() {
        let command = OnboardingStrings.text("welcome.spoken.command")
        let actions = Self.rows.first { $0.id == "actions" }
        #expect(actions?.spokenKeys == "\(command) K")
        let range = Self.rows.first { $0.id == "pickTarget" }?.spokenKeys ?? ""
        #expect(range.contains("\(command) 1") && range.contains("\(command) 4"))
        let refine = Self.rows.first { $0.id == "refine" }?.spokenKeys ?? ""
        #expect(refine.contains(OnboardingStrings.text("welcome.keys.refine.sample")))
        #expect(refine.contains(OnboardingStrings.text("welcome.spoken.return")))
    }

    @Test func twoShortcutsALineInReadingOrder() {
        let lines = WelcomeKeysStepView.lines(of: Self.groups[0].rows)
        #expect(lines.map(\.first.id) == ["improve", "nextTarget"])
        #expect(lines.map { $0.second?.id } == ["newLine", "pickTarget"])
        let odd = WelcomeKeysStepView.lines(of: Array(Self.groups[0].rows.prefix(3)))
        #expect(odd.count == 2)
        #expect(odd.last?.second == nil)
    }
}
