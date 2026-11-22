import AppKit
@testable import PIApp
import PICore
import PIProviders
import Testing

/// Renders every Settings pane, and the remove-key dialog, light and dark, English and Spanish,
/// as PNGs for a person to look at. It checks nothing by itself. Opt-in (`StatusItemLiveTests`
/// writes the menu bar item to the same folder):
///
///     PI_SETTINGS_SNAPSHOTS=<folder> swift test --filter SettingsSnapshotTests
@Suite(.serialized)
struct SettingsSnapshotTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["PI_SETTINGS_SNAPSHOTS"].map { URL(filePath: $0) }

    enum Variant: String, CaseIterable {
        /// Keys set, default preset.
        case standard
        /// The other states: a custom model, a rejected key, warnings.
        case states
    }

    @Test(.enabled(if: folder != nil))
    func renderEveryPane() async throws {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        defer { SettingsStrings.previewLanguage = nil }

        for language in ["en", "es"] {
            SettingsStrings.previewLanguage = language
            for dark in [false, true] {
                for variant in Variant.allCases {
                    for pane in SettingsPane.allCases {
                        if variant == .states, ![.general, .engine, .instructions].contains(pane) { continue }
                        let fixture = makeFixture(variant)
                        fixture.model.selectedPane = pane
                        let controller = SettingsWindowController(context: fixture.context, model: fixture.model, activator: FakeActivator())
                        let name = "settings-\(pane.rawValue)-\(variant.rawValue)-\(language)-\(dark ? "dark" : "light").png"
                        try await capture(try #require(controller.window), dark: dark, to: folder.appending(path: name))
                        if pane == .engine, variant == .states {
                            fixture.model.dialog = SettingsDialog(
                                title: SettingsStrings.text("settings.key.remove.title", "OpenAI"),
                                message: SettingsStrings.text("settings.key.remove.message", "OpenAI"),
                                symbol: "key",
                                actions: [
                                    .init(title: SettingsStrings.text("settings.key.cancel"), role: .cancel) {},
                                    .init(title: SettingsStrings.text("settings.key.remove"), role: .destructive) {},
                                ]
                            )
                            let dialogName = "settings-engine-dialog-\(language)-\(dark ? "dark" : "light").png"
                            try await capture(try #require(controller.window), dark: dark, to: folder.appending(path: dialogName))
                        }
                        controller.window?.orderOut(nil)
                    }
                }
            }
        }
    }

    private let hotKeys = HotKeyCenter()

    private func makeFixture(_ variant: Variant) -> SettingsFixture {
        switch variant {
        case .standard:
            let fixture = SettingsFixture(
                vault: FakeVault([
                    .anthropic: .valid(masked: "sk-…a1b2"),
                    .openai: .missing,
                ]),
                registersShortcut: true,
                hotKeys: hotKeys
            )
            fixture.settings.customInstructions = "Always write in English\nUse XML tags"
            return fixture
        case .states:
            let fixture = SettingsFixture(vault: FakeVault([
                .anthropic: .unverified(masked: "sk-…a1b2"),
                .openai: .invalid(masked: "sk-…9f3c"),
            ]))
            fixture.settings.preset = .custom(model: "claude-fable-5-2", effort: .high)
            fixture.settings.customInstructions = String(
                repeating: "Write prompts as a senior engineer would brief a colleague. ",
                count: 31
            ).trimmingCharacters(in: .whitespaces)
            fixture.context.shortcut.recorder.conflict = .usedByMenuItem("Settings…")
            fixture.context.keyEntry(for: .anthropic).draft = ""
            return fixture
        }
    }

    /// Captures `window` as the window server composites it, so Liquid Glass shows as it does on
    /// screen; falls back to drawing the view hierarchy (no glass) when screen capture is not
    /// allowed. The window is put on screen for the capture and taken off again by the caller.
    private func capture(_ window: NSWindow, dark: Bool, to url: URL) async throws {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        window.makeFirstResponder(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.displayIfNeeded()

        let screencapture = Process()
        screencapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try screencapture.run()
        screencapture.waitUntilExit()
        if screencapture.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { return }

        let view = try #require(window.contentView?.superview ?? window.contentView)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
