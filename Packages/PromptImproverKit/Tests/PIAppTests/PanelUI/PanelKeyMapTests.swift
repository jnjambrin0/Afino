@testable import PIApp
import PIDesign
import Testing

/// The panel's whole keyboard: every screen against every chord, what is not consumed, and that
/// the shortcuts shown come from the same table.
struct PanelKeyMapTests {
    // MARK: Chords

    private static let ret = KeyChord(.returnKey)
    private static let cmdRet = KeyChord(.returnKey, .command)
    private static let shiftRet = KeyChord(.returnKey, .shift)
    private static let optRet = KeyChord(.returnKey, .option)
    private static let esc = KeyChord(.escape)
    private static let tab = KeyChord(.tab)
    private static let shiftTab = KeyChord(.tab, .shift)
    private static let up = KeyChord(.upArrow)
    private static let down = KeyChord(.downArrow)
    private static let cmdDown = KeyChord(.downArrow, .command)
    private static let cmdDelete = KeyChord(.delete, .command)

    private static func cmd(_ key: String) -> KeyChord { KeyChord(.char(key), .command) }

    private static let targetBindings: [(KeyChord, PanelCommand)] = (0..<9).map { (cmd(String($0 + 1)), .selectTarget($0)) }

    /// The complete table, screen by screen, written out independently of `PanelKeyMap`.
    private static let expected: [PanelScreen: [(KeyChord, PanelCommand)]] = [
        .compose: [
            (ret, .primary), (cmdRet, .primary), (shiftRet, .insertNewline), (optRet, .insertNewline),
            (esc, .escape), (tab, .nextTarget), (shiftTab, .previousTarget),
            (up, .recallOlder), (down, .recallNewer),
            (cmd("k"), .toggleActions), (cmd("y"), .toggleHistory), (cmd(","), .openSettings),
        ] + targetBindings,
        .running: [
            (esc, .escape), (cmd("."), .stop), (cmd("c"), .copy), (cmd("o"), .toggleOriginal),
            (up, .scrollUp), (down, .scrollDown), (cmdDown, .jumpToEnd), (cmd("k"), .toggleActions),
        ],
        .result: [
            (ret, .primary), (cmdRet, .copyAndClose), (esc, .escape), (cmd("c"), .copy),
            (cmd("r"), .regenerate), (cmd("e"), .editOriginal), (cmd("o"), .toggleOriginal), (cmd("n"), .newPrompt),
            (cmd("["), .previousVersion), (cmd("]"), .nextVersion),
            (up, .scrollUp), (down, .scrollDown), (cmdDown, .jumpToEnd),
            (cmd("k"), .toggleActions), (cmd("y"), .toggleHistory), (cmd(","), .openSettings),
        ] + targetBindings,
        .failed: problemBindings,
        .stopped: problemBindings,
        .setup: [(ret, .primary), (cmd("v"), .pasteKey), (esc, .escape), (cmd(","), .openSettings)],
        .history: [
            (ret, .historyOpen), (up, .historyPrevious), (down, .historyNext), (cmdDelete, .historyDelete),
            (cmd("z"), .undoDelete), (esc, .escape), (cmd("y"), .toggleHistory), (cmd(","), .openSettings),
        ],
    ]

    private static let problemBindings: [(KeyChord, PanelCommand)] = [
        (ret, .primary), (cmdRet, .copyAndClose), (esc, .escape), (cmd("c"), .copy),
        (cmd("r"), .retry), (cmd("e"), .editOriginal), (cmd("o"), .toggleOriginal), (cmd("n"), .newPrompt),
        (up, .scrollUp), (down, .scrollDown), (cmdDown, .jumpToEnd),
        (cmd("k"), .toggleActions), (cmd("y"), .toggleHistory), (cmd(","), .openSettings),
    ] + targetBindings

    /// Every chord any screen uses, plus keys that belong to the text views (typing, editing,
    /// selecting), which the panel must never take.
    private static let universe: [KeyChord] = {
        var chords = expected.values.flatMap { $0.map(\.0) }
        chords += [
            KeyChord(.char("a")), KeyChord(.char("k")), KeyChord(.space), KeyChord(.delete),
            KeyChord(.leftArrow), KeyChord(.rightArrow), KeyChord(.upArrow, .shift), KeyChord(.downArrow, .option),
            cmd("a"), cmd("x"), cmd("v"), cmd("z"), KeyChord(.char("z"), [.command, .shift]), cmd("w"), cmd("q"),
            cmd("0"), cmd("b"), KeyChord(.returnKey, .control), KeyChord(.returnKey, [.command, .shift]),
            KeyChord(.escape, .command), KeyChord(.upArrow, .command), KeyChord(.tab, .control), KeyChord(.delete, .option),
        ]
        var unique: [KeyChord] = []
        for chord in chords where !unique.contains(chord) { unique.append(chord) }
        return unique
    }()

    /// A context in which every conditional command applies.
    private static func permissive(_ screen: PanelScreen) -> PanelKeyContext {
        var context = PanelKeyContext(screen: screen)
        context.isPrimaryEnabled = true
        context.canRecallOlder = true
        context.canRecallNewer = true
        context.targetCount = 9
        context.historyEnabled = true
        context.hasDisplayedText = true
        context.hasResultSelection = true
        context.versionCount = 3
        context.shownVersion = 1
        context.hasHistorySelection = true
        context.historyCount = 3
        context.canUndoDelete = true
        return context
    }

    // MARK: The table

    @Test(arguments: PanelScreen.allCases)
    func everyChordOnEveryScreenMapsAsTheTableSays(screen: PanelScreen) throws {
        let table = try #require(Self.expected[screen])
        let context = Self.permissive(screen)
        for chord in Self.universe {
            let expected = table.first { $0.0 == chord }?.1
            #expect(
                PanelKeyMap.command(for: chord, in: context) == expected,
                "\(screen): \(ShortcutGlyphFormatter.string(for: chord))")
        }
    }

    @Test(arguments: PanelScreen.allCases)
    func theTableHasNoBindingTheTestDoesNotKnow(screen: PanelScreen) throws {
        let table = try #require(Self.expected[screen])
        let bindings = PanelKeyMap.bindings(in: screen)
        #expect(bindings.count == table.count)
        for binding in bindings {
            #expect(table.contains { $0.0 == binding.chord && $0.1 == binding.command }, "\(screen): \(binding.command)")
        }
    }

    @Test(arguments: PanelScreen.allCases)
    func everyDisplayedChordTriggersItsCommand(screen: PanelScreen) {
        let context = Self.permissive(screen)
        for binding in PanelKeyMap.bindings(in: screen) {
            let chord = PanelKeyMap.chord(for: binding.command, in: screen)
            #expect(chord != nil)
            if let chord {
                #expect(PanelKeyMap.command(for: chord, in: context) == binding.command)
            }
        }
    }

    @Test func returnIsTheChordShownForImproveNotCommandReturn() {
        #expect(PanelKeyMap.chord(for: .primary, in: .compose) == Self.ret)
        #expect(PanelKeyMap.chord(for: .escape, in: .running) == Self.esc)
        #expect(PanelKeyMap.chord(for: .copyAndClose, in: .result) == Self.cmdRet)
        #expect(PanelKeyMap.chord(for: .stop, in: .compose) == nil)
        #expect(PanelKeyMap.chord(for: .regenerate, in: .failed) == nil)
        #expect(PanelKeyMap.chord(for: .retry, in: .failed) == Self.cmd("r"))
    }

    // MARK: A floating card takes the arrows, Return and Esc

    @Test(arguments: PanelScreen.allCases)
    func anOpenCardTakesOnlyItsOwnKeys(screen: PanelScreen) {
        var context = Self.permissive(screen)
        context.isMenuOpen = true
        let menu: [(KeyChord, PanelCommand)] = [
            (Self.up, .menuPrevious), (Self.down, .menuNext), (Self.ret, .menuExecute),
            (Self.esc, .escape), (Self.cmd("k"), .toggleActions),
        ]
        for chord in Self.universe {
            #expect(PanelKeyMap.command(for: chord, in: context) == menu.first { $0.0 == chord }?.1)
        }
        #expect(PanelKeyMap.menuChord(for: .menuExecute) == Self.ret)
    }

    // MARK: Inapplicable commands are not consumed

    @Test func improveIsNotConsumedWhileTheDraftCannotBeSubmitted() {
        var context = Self.permissive(.compose)
        context.isPrimaryEnabled = false
        #expect(PanelKeyMap.command(for: Self.ret, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmdRet, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.shiftRet, in: context) == .insertNewline)
    }

    @Test func tabIsFocusTraversalWithFullKeyboardAccessOrOneTarget() {
        var context = Self.permissive(.compose)
        context.isFullKeyboardAccessEnabled = true
        #expect(PanelKeyMap.command(for: Self.tab, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.shiftTab, in: context) == nil)

        context = Self.permissive(.compose)
        context.targetCount = 1
        #expect(PanelKeyMap.command(for: Self.tab, in: context) == nil)
    }

    @Test(arguments: [PanelScreen.result, .failed, .stopped, .running, .history, .setup])
    func tabIsNeverTakenOutsideCompose(screen: PanelScreen) {
        #expect(PanelKeyMap.command(for: Self.tab, in: Self.permissive(screen)) == nil)
    }

    @Test func onlyTargetsThatExistAreSelectable() {
        var context = Self.permissive(.compose)
        context.targetCount = 4
        #expect(PanelKeyMap.command(for: Self.cmd("4"), in: context) == .selectTarget(3))
        #expect(PanelKeyMap.command(for: Self.cmd("5"), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("9"), in: context) == nil)
    }

    @Test func arrowsInADraftMoveTheCaretUnlessItIsEmptyOrRecalled() {
        var context = Self.permissive(.compose)
        context.canRecallOlder = false
        context.canRecallNewer = false
        #expect(PanelKeyMap.command(for: Self.up, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.down, in: context) == nil)

        context.canRecallOlder = true
        #expect(PanelKeyMap.command(for: Self.up, in: context) == .recallOlder)
        #expect(PanelKeyMap.command(for: Self.down, in: context) == nil)
    }

    @Test(arguments: [PanelScreen.compose, .result, .failed, .stopped, .history])
    func historyIsNotOfferedWhenItIsOff(screen: PanelScreen) {
        var context = Self.permissive(screen)
        context.historyEnabled = false
        #expect(PanelKeyMap.command(for: Self.cmd("y"), in: context) == nil)
    }

    @Test func copyWhileRunningIsOnlyForASelection() {
        var context = Self.permissive(.running)
        context.hasResultSelection = false
        #expect(PanelKeyMap.command(for: Self.cmd("c"), in: context) == nil)
        context.hasResultSelection = true
        #expect(PanelKeyMap.command(for: Self.cmd("c"), in: context) == .copy)
    }

    @Test(arguments: [PanelScreen.running, .result, .failed, .stopped])
    func aFieldsOwnSelectionKeepsCommandC(screen: PanelScreen) {
        var context = Self.permissive(screen)
        context.hasFieldSelection = true
        #expect(PanelKeyMap.command(for: Self.cmd("c"), in: context) == nil)
    }

    @Test(arguments: [PanelScreen.failed, .stopped])
    func withoutPartialTextThereIsNothingToCopyOrScroll(screen: PanelScreen) {
        var context = Self.permissive(screen)
        context.hasDisplayedText = false
        context.hasResultSelection = false
        #expect(PanelKeyMap.command(for: Self.cmd("c"), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmdRet, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.up, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmdDown, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.ret, in: context) == .primary)
    }

    @Test func aRateLimitsWaitLeavesReturnAlone() {
        var context = Self.permissive(.failed)
        context.isPrimaryEnabled = false
        #expect(PanelKeyMap.command(for: Self.ret, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("e"), in: context) == .editOriginal)
    }

    @Test func versionKeysStopAtTheEnds() {
        var context = Self.permissive(.result)
        context.versionCount = 3
        context.shownVersion = 0
        #expect(PanelKeyMap.command(for: Self.cmd("["), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("]"), in: context) == .nextVersion)
        context.shownVersion = 2
        #expect(PanelKeyMap.command(for: Self.cmd("]"), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("["), in: context) == .previousVersion)
        context.versionCount = 1
        context.shownVersion = 0
        #expect(PanelKeyMap.command(for: Self.cmd("["), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("]"), in: context) == nil)
    }

    @Test func theHistoryNeedsASelectionAnEntryAndSomethingToUndo() {
        var context = Self.permissive(.history)
        context.hasHistorySelection = false
        context.historyCount = 0
        context.canUndoDelete = false
        #expect(PanelKeyMap.command(for: Self.ret, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmdDelete, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.up, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.down, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("z"), in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.esc, in: context) == .escape)
    }

    @Test func theKeyCardSavesOnlyWhenItCan() {
        var context = Self.permissive(.setup)
        context.isPrimaryEnabled = false
        #expect(PanelKeyMap.command(for: Self.ret, in: context) == nil)
        #expect(PanelKeyMap.command(for: Self.cmd("v"), in: context) == .pasteKey)
    }

    @Test(arguments: PanelScreen.allCases)
    func escapeIsAlwaysTaken(screen: PanelScreen) {
        var context = PanelKeyContext(screen: screen)
        context.isPrimaryEnabled = false
        #expect(PanelKeyMap.command(for: Self.esc, in: context) == .escape)
    }

    // MARK: Settings › Shortcuts

    @Test func theReferenceHasThreeGroupsBuiltFromTheTable() {
        let groups = PanelKeyMap.referenceGroups()
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { !$0.rows.isEmpty })
        #expect(Set(groups.map(\.title)).count == 3)
        for group in groups {
            #expect(Set(group.rows.map(\.label)).count == group.rows.count, "labels repeat in \(group.title)")
        }
        let chords = groups.flatMap(\.rows).map(\.chord)
        #expect(chords.contains(Self.ret))
        #expect(chords.contains(Self.cmdRet))
        #expect(chords.contains(Self.cmd("k")))
        #expect(chords.contains(Self.cmd(".")))
    }
}
