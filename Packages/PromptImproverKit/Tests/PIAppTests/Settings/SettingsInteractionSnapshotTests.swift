import AppKit
@testable import PIApp
import PICore
import PIProviders
import Testing

/// Captures the Settings window in use, for a person to review: every pane and control state
/// (hover, press, keyboard focus, open menus, dialogs, recording, checking, invalid, disabled,
/// Increase Contrast, Reduce Transparency) as PNGs, the accessibility tree as VoiceOver reads it
/// as text outlines, and every animated interaction as a folder of frames. Beyond a select's
/// menu choosing on a click and closing on a click outside, it checks only that the script could
/// drive the window.
///
/// Opt-in, and slow; capturing needs Screen Recording permission for the app running the tests:
///
///     PI_SETTINGS_INTERACTIONS=<folder> swift test --filter SettingsInteractionSnapshotTests
@Suite(.serialized)
struct SettingsInteractionSnapshotTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["PI_SETTINGS_INTERACTIONS"].map { URL(filePath: $0) }

    private let hotKeys = HotKeyCenter()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Registers the process with accessibility, so the AX tree can be read.
        NSApplication.shared.finishLaunching()
    }

    /// A valid Anthropic key, no OpenAI key, the shortcut registered and two lines of instructions.
    private func standardFixture() -> SettingsFixture {
        let fixture = SettingsFixture(
            vault: FakeVault([.anthropic: .valid(masked: "sk-…a1b2"), .openai: .missing]),
            registersShortcut: true,
            hotKeys: hotKeys
        )
        fixture.settings.customInstructions = "Always write in English\nUse XML tags"
        return fixture
    }

    /// The other states: an unchecked and a rejected key, a custom model, and instructions near
    /// the limit.
    private func statesFixture() -> SettingsFixture {
        let fixture = SettingsFixture(vault: FakeVault([
            .anthropic: .unverified(masked: "sk-…a1b2"),
            .openai: .invalid(masked: "sk-…9f3c"),
        ]))
        fixture.settings.preset = .custom(model: "claude-fable-5-2", effort: .high)
        fixture.settings.customInstructions = String(
            repeating: "Write prompts as a senior engineer would brief a colleague. ",
            count: 31
        ).trimmingCharacters(in: .whitespaces)
        return fixture
    }

    /// A Settings window for `fixture` on `pane`, laid out and with nothing focused.
    private func open(
        _ fixture: SettingsFixture,
        pane: SettingsPane,
        appearance: NSAppearance.Name = .aqua,
        overrides: SettingsWindowDriver.Overrides = .init()
    ) throws -> SettingsWindowDriver {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fixture.model.selectedPane = pane
        let window = SettingsWindowDriver.settingsWindow(fixture, appearance: appearance, overrides: overrides)
        let driver = SettingsWindowDriver(window: window, folder: folder)
        driver.spin(0.8)
        window.makeFirstResponder(nil)
        driver.spin(0.1)
        return driver
    }

    private func text(_ key: String) -> String { SettingsStrings.text(key) }

    // MARK: States

    @Test(.enabled(if: folder != nil))
    func states() async throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try await generalStates(name, appearance)
            try await engineStates(name, appearance)
            try otherPaneStates(name, appearance)
        }
    }

    /// Increase Contrast (the high-contrast appearance and SwiftUI's contrast) and Reduce
    /// Transparency (SwiftUI's setting; Liquid Glass itself follows only the system's).
    @Test(.enabled(if: folder != nil))
    func accessibilitySettings() async throws {
        let contrast: [(String, NSAppearance.Name)] = [("hc-light", .accessibilityHighContrastAqua), ("hc-dark", .accessibilityHighContrastDarkAqua)]
        for (name, appearance) in contrast {
            for pane in [SettingsPane.general, .engine] {
                let driver = try open(statesFixture(), pane: pane, appearance: appearance, overrides: .init(increaseContrast: true))
                try driver.capture("\(name)-\(pane.rawValue)")
                if pane == .engine {
                    try driver.click("Claude Fable 5.2")
                    driver.spin(0.4)
                    try driver.capture("\(name)-engine-select-open")
                    driver.press(.escape)
                    driver.spin(0.3)
                }
                driver.window.orderOut(nil)
            }
        }
        for (name, appearance) in [("rt-light", NSAppearance.Name.aqua), ("rt-dark", .darkAqua)] {
            let driver = try open(standardFixture(), pane: .engine, appearance: appearance, overrides: .init(reduceTransparency: true))
            try driver.capture("\(name)-engine")
            try driver.click(text("settings.key.remove"))
            driver.spin(0.5)
            try driver.capture("\(name)-engine-dialog")
            driver.press(.escape)
            driver.spin(0.3)
            driver.window.orderOut(nil)
        }
    }

    private func generalStates(_ name: String, _ appearance: NSAppearance.Name) async throws {
        let fixture = standardFixture()
        let driver = try open(fixture, pane: .general, appearance: appearance)
        try driver.capture("\(name)-general-rest")
        try driver.writeOutline("\(name)-general-outline")

        // Hover and press: a select, a chip, a sidebar row.
        driver.move(to: try driver.point(of: "Last used"))
        driver.spin(0.2)
        try driver.capture("\(name)-general-hover-select")
        driver.mouseDown(at: try driver.point(of: "Last used"))
        driver.spin(0.15)
        try driver.capture("\(name)-general-press-select")
        driver.mouseUp(at: NSPoint(x: 4, y: 4))
        driver.move(to: try driver.point(of: text("settings.general.theme.light")))
        driver.spin(0.2)
        try driver.capture("\(name)-general-hover-chip")
        driver.mouseDown(at: try driver.point(of: text("settings.general.theme.light")))
        driver.spin(0.15)
        try driver.capture("\(name)-general-press-chip")
        driver.mouseUp(at: NSPoint(x: 4, y: 4))
        driver.move(to: try driver.point(of: SettingsPane.engine.title))
        driver.spin(0.2)
        try driver.capture("\(name)-general-hover-sidebar")
        driver.moveAway()

        // The select's menu, with the highlight moved by the keyboard.
        try driver.click("Last used")
        driver.spin(0.4)
        try driver.capture("\(name)-general-select-open")
        driver.press(.down)
        driver.press(.down)
        driver.spin(0.1)
        try driver.capture("\(name)-general-select-highlight")
        driver.press(.escape)
        driver.spin(0.3)

        // A click on a row chooses it; a click outside closes the menu without acting.
        var log: [String] = []
        try driver.click("Last used")
        driver.spin(0.4)
        try driver.click("Claude")
        driver.spin(0.4)
        log.append("after clicking the Claude row: defaultTarget = \(fixture.settings.defaultTarget)")
        #expect(fixture.settings.defaultTarget == .fixed(id: "claude"), "a click on a row chooses it")
        try driver.capture("\(name)-general-select-row-clicked")
        // The menu is modal for accessibility: find the outside point while it is closed.
        let theme = try driver.point(of: text("settings.general.theme.title"), role: "AXStaticText")
        try driver.click("Claude")
        driver.spin(0.4)
        let historyBefore = fixture.settings.historyEnabled
        driver.click(theme)
        driver.spin(0.4)
        let stillOpen = driver.element("GPT") != nil
        log.append("after clicking outside: menu open = \(stillOpen), history \(historyBefore) → \(fixture.settings.historyEnabled)")
        #expect(!stillOpen, "a click outside closes the menu")
        #expect(fixture.settings.historyEnabled == historyBefore, "…and acts on nothing else")
        try driver.capture("\(name)-general-select-outside-clicked")
        driver.press(.escape)
        driver.spin(0.3)
        fixture.settings.defaultTarget = .lastUsed
        driver.spin(0.2)
        try log.joined(separator: "\n").write(to: driver.folder.appending(path: "\(name)-select-clicks.txt"), atomically: true, encoding: .utf8)

        // The recorder: recording, then a conflict.
        try driver.click(text("settings.shortcut.record.accessibility"))
        driver.spin(0.2)
        try driver.capture("\(name)-general-recorder-recording")
        try driver.click(text("settings.shortcut.record.accessibility"))
        driver.spin(0.2)
        fixture.context.shortcut.recorder.conflict = .usedByMenuItem("Settings…")
        driver.spin(0.2)
        try driver.capture("\(name)-general-recorder-conflict")
        fixture.context.shortcut.recorder.conflict = nil
        driver.spin(0.2)

        // Keyboard focus on every control Tab reaches (Full Keyboard Access).
        for index in driver.focusableControls().indices where driver.focusControl(index) {
            try driver.capture("\(name)-general-focus-\(index)")
        }
        driver.window.makeFirstResponder(nil)

        // The bottom of the pane, then "Cleared".
        driver.scrollPane(toEnd: true)
        try driver.capture("\(name)-general-bottom")
        try driver.click(text("settings.general.clearHistory.button"))
        await driver.wait(0.4)
        try driver.capture("\(name)-general-cleared")
        driver.window.orderOut(nil)

        // Open at login on.
        let login = standardFixture()
        login.launchAtLogin.setEnabled(true)
        let loginDriver = try open(login, pane: .general, appearance: appearance)
        try loginDriver.capture("\(name)-general-login-on")
        loginDriver.window.orderOut(nil)
    }

    private func engineStates(_ name: String, _ appearance: NSAppearance.Name) async throws {
        let fixture = standardFixture()
        let driver = try open(fixture, pane: .engine, appearance: appearance)
        try driver.capture("\(name)-engine-rest")
        try driver.writeOutline("\(name)-engine-outline")

        driver.move(to: try driver.point(of: text("settings.key.check")))
        driver.spin(0.2)
        try driver.capture("\(name)-engine-hover-check")
        driver.mouseDown(at: try driver.point(of: text("settings.key.check")))
        driver.spin(0.15)
        try driver.capture("\(name)-engine-press-check")
        driver.mouseUp(at: NSPoint(x: 4, y: 4))
        driver.moveAway()

        // Keyboard focus on the key rows.
        for index in driver.focusableControls().indices where driver.focusControl(index) {
            try driver.capture("\(name)-engine-focus-\(index)")
        }
        driver.window.makeFirstResponder(nil)
        driver.spin(0.2)

        // Checking.
        fixture.vault.holdsChecks = true
        try driver.click(text("settings.key.check"))
        await driver.wait(0.3)
        try driver.capture("\(name)-engine-checking")
        fixture.vault.resume()
        fixture.vault.holdsChecks = false
        await driver.wait(0.3)
        try driver.capture("\(name)-engine-checked")

        // Replacing the stored key: editing with Save and Cancel, then typed text.
        try driver.click(SettingsStrings.text("settings.key.accessibility", "Anthropic"))
        driver.spin(0.3)
        try driver.capture("\(name)-engine-editing")
        driver.press(.text("sk-ant-api03-new"))
        driver.spin(0.2)
        try driver.capture("\(name)-engine-typed")
        try driver.click(text("settings.key.cancel"))
        driver.spin(0.2)

        // Remove → the dialog.
        try driver.click(text("settings.key.remove"))
        driver.spin(0.5)
        try driver.capture("\(name)-engine-dialog")
        try driver.writeOutline("\(name)-engine-dialog-outline")
        driver.press(.escape)
        driver.spin(0.4)
        driver.window.orderOut(nil)

        // Custom model: its select open, a long and an empty model id.
        let states = statesFixture()
        let statesDriver = try open(states, pane: .engine, appearance: appearance)
        try statesDriver.capture("\(name)-engine-custom")
        try statesDriver.click("Claude Fable 5.2")
        statesDriver.spin(0.4)
        try statesDriver.capture("\(name)-engine-custom-select-open")
        statesDriver.press(.escape)
        statesDriver.spin(0.3)
        states.settings.preset = .custom(model: "anthropic.claude-fable-5-2-20261101-v1:0-extended-thinking", effort: .high)
        statesDriver.spin(0.3)
        try statesDriver.capture("\(name)-engine-long-model")
        states.settings.preset = .custom(model: "", effort: .high)
        statesDriver.spin(0.3)
        try statesDriver.capture("\(name)-engine-empty-model")
        statesDriver.scrollPane(toEnd: true)
        try statesDriver.capture("\(name)-engine-custom-bottom")
        statesDriver.window.orderOut(nil)
    }

    private func otherPaneStates(_ name: String, _ appearance: NSAppearance.Name) throws {
        let nearLimit = try open(statesFixture(), pane: .instructions, appearance: appearance)
        try nearLimit.capture("\(name)-instructions-near-limit")
        nearLimit.window.orderOut(nil)

        let fixture = standardFixture()
        let driver = try open(fixture, pane: .instructions, appearance: appearance)
        try driver.capture("\(name)-instructions-rest")
        try driver.writeOutline("\(name)-instructions-outline")
        try driver.click(text("settings.instructions.editor.accessibility"))
        driver.spin(0.3)
        try driver.capture("\(name)-instructions-editing")
        driver.window.makeFirstResponder(nil)
        fixture.settings.customInstructionsEnabled = false
        driver.spin(0.3)
        try driver.capture("\(name)-instructions-off")
        driver.window.orderOut(nil)

        let shortcuts = try open(standardFixture(), pane: .shortcuts, appearance: appearance)
        try shortcuts.capture("\(name)-shortcuts-rest")
        try shortcuts.writeOutline("\(name)-shortcuts-outline")
        shortcuts.window.orderOut(nil)

        let about = try open(standardFixture(), pane: .about, appearance: appearance)
        try about.capture("\(name)-about-rest")
        try about.writeOutline("\(name)-about-outline")
        about.move(to: try about.point(of: text("settings.about.website")))
        about.spin(0.2)
        try about.capture("\(name)-about-hover-link")
        for index in about.focusableControls().indices where about.focusControl(index) {
            try about.capture("\(name)-about-focus-\(index)")
        }
        about.window.makeFirstResponder(nil)
        try about.click(text("settings.about.acknowledgements"))
        about.spin(0.5)
        try about.capture("\(name)-about-dialog")
        about.window.orderOut(nil)
    }

    // MARK: Motion

    /// One folder of frames per interaction, each frame named by its time in milliseconds.
    @Test(.enabled(if: folder != nil))
    func motion() async throws {
        let fixture = standardFixture()
        let driver = try open(fixture, pane: .general)

        // The switch, on and off.
        let login = try driver.topLeftRect(of: text("settings.general.login.title"), role: "AXCheckBox")
        try await driver.record("motion-switch", region: login.insetBy(dx: -24, dy: -12)) {
            try driver.click(text("settings.general.login.title"), role: "AXCheckBox")
            driver.spin(0.6)
            try driver.click(text("settings.general.login.title"), role: "AXCheckBox")
            driver.spin(0.6)
        }

        // Theme chips: Light, Dark, System.
        let theme = try driver.topLeftRect(of: text("settings.general.theme.title"), role: "AXStaticText")
        let chipRegion = CGRect(x: 420, y: theme.minY - 14, width: driver.window.frame.width - 428, height: theme.height + 28)
        try await driver.record("motion-chips", region: chipRegion) {
            for key in ["settings.general.theme.light", "settings.general.theme.dark", "settings.general.theme.system"] {
                try driver.click(text(key))
                driver.moveAway()
                driver.spin(0.5)
            }
        }

        // The select's menu: open, Esc, open, click outside.
        let select = try driver.topLeftRect(of: "Last used")
        let menuRegion = CGRect(x: 380, y: select.minY - 16, width: driver.window.frame.width - 388, height: 250)
        try await driver.record("motion-select", region: menuRegion) {
            try driver.click("Last used")
            driver.spin(0.5)
            driver.press(.escape)
            driver.spin(0.4)
            let outside = try driver.point(of: text("settings.general.prompts.section"))
            try driver.click("Last used")
            driver.spin(0.4)
            driver.click(outside)
            driver.spin(0.4)
        }
        driver.press(.escape)
        driver.spin(0.3)

        // Recorder: start, cancel.
        let recorder = try driver.topLeftRect(of: text("settings.shortcut.record.accessibility"))
        try await driver.record("motion-recorder", region: recorder.insetBy(dx: -30, dy: -10)) {
            try driver.click(text("settings.shortcut.record.accessibility"))
            driver.spin(0.5)
            try driver.click(text("settings.shortcut.record.accessibility"))
            driver.spin(0.5)
        }

        // Pane switching through the sidebar and ⌘1 / ⌘2, at 1×.
        try await driver.record("motion-panes", scale: 1) {
            try driver.click(SettingsPane.engine.title)
            driver.spin(0.5)
            try driver.click(SettingsPane.instructions.title)
            driver.spin(0.5)
            driver.press(.command("1"))
            driver.spin(0.5)
            driver.press(.command("2"))
            driver.spin(0.5)
        }
        driver.press(.command("1"))
        driver.spin(0.3)

        // Clear history → "Cleared".
        driver.scrollPane(toEnd: true)
        let clear = try driver.topLeftRect(of: text("settings.general.clearHistory.button"))
        try await driver.record("motion-cleared", region: clear.insetBy(dx: -80, dy: -14)) {
            try driver.click(text("settings.general.clearHistory.button"))
            await driver.wait(0.6)
        }
        driver.window.orderOut(nil)

        // Engine: hover and press on a button.
        let engine = try open(standardFixture(), pane: .engine)
        let check = try engine.topLeftRect(of: text("settings.key.check"))
        let keyRegion = CGRect(x: 232, y: check.minY - 64, width: engine.window.frame.width - 240, height: 110)
        try await engine.record("motion-button", region: keyRegion) {
            let point = try engine.point(of: text("settings.key.check"))
            engine.move(to: point)
            engine.spin(0.3)
            engine.mouseDown(at: point)
            engine.spin(0.3)
            engine.mouseUp(at: NSPoint(x: 4, y: 4))
            engine.moveAway()
            engine.spin(0.3)
        }
        engine.window.orderOut(nil)

        // Check with the provider held, then answered; the dialog; presets.
        let checking = standardFixture()
        let checkingDriver = try open(checking, pane: .engine)
        let checkRow = try checkingDriver.topLeftRect(of: text("settings.key.check"))
        checking.vault.holdsChecks = true
        try await checkingDriver.record("motion-check", region: CGRect(x: 232, y: checkRow.minY - 64, width: checkingDriver.window.frame.width - 240, height: 110)) {
            try checkingDriver.click(text("settings.key.check"))
            await checkingDriver.wait(0.8)
            checking.vault.resume()
            checking.vault.holdsChecks = false
            await checkingDriver.wait(0.6)
        }
        try await checkingDriver.record("motion-dialog", scale: 1) {
            try checkingDriver.click(text("settings.key.remove"))
            checkingDriver.spin(0.6)
            try checkingDriver.click(text("settings.key.cancel"))
            checkingDriver.spin(0.6)
        }
        try await checkingDriver.record("motion-preset", scale: 1) {
            try checkingDriver.click(text("settings.engine.preset.custom"))
            checkingDriver.spin(0.6)
            try checkingDriver.click(text("settings.engine.preset.balanced"))
            checkingDriver.spin(0.6)
        }
        checkingDriver.window.orderOut(nil)

        // Reduce Motion: the switch and the chips.
        let reduced = try open(standardFixture(), pane: .general, overrides: .init(reduceMotion: true))
        let reducedSwitch = try reduced.topLeftRect(of: text("settings.general.login.title"), role: "AXCheckBox")
        try await reduced.record("motion-reduced-switch", region: reducedSwitch.insetBy(dx: -24, dy: -12)) {
            try reduced.click(text("settings.general.login.title"), role: "AXCheckBox")
            reduced.spin(0.5)
        }
        let reducedTheme = try reduced.topLeftRect(of: text("settings.general.theme.title"), role: "AXStaticText")
        let reducedRegion = CGRect(x: 420, y: reducedTheme.minY - 14, width: reduced.window.frame.width - 428, height: reducedTheme.height + 28)
        try await reduced.record("motion-reduced-chips", region: reducedRegion) {
            try reduced.click(text("settings.general.theme.dark"))
            reduced.spin(0.5)
        }
        reduced.window.orderOut(nil)

        // Opening the window: nothing may animate on first appearance.
        let first = standardFixture()
        first.model.selectedPane = .engine
        let folder = try #require(Self.folder)
        let window = SettingsWindowDriver.settingsWindow(first, appearance: .aqua)
        let opening = SettingsWindowDriver(window: window, folder: folder)
        try await opening.record("motion-open", scale: 1) {
            opening.spin(0.6)
        }
        window.orderOut(nil)
    }
}
