import AppKit
import Observation
import os
import PICore
import PIDesign
import PIFoundation
import PIPrompts
import SwiftUI

/// The Settings window: an AppKit-owned window with a transparent, full-size title bar (the
/// traffic lights stay), a floating glass sidebar and the selected pane. The window title follows
/// the pane (Window menu, VoiceOver) while the title bar shows none.
///
/// AppKit owns the window instead of SwiftUI's `Settings` scene: the app is an accessory
/// (`LSUIElement`) app, whose scene windows can open behind other apps' windows.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsWindowModel
    private let context: SettingsContext
    private let activator: any AppActivating

    /// - Parameter shortcutReference: The panel's keyboard shortcuts, listed in Settings › Shortcuts.
    convenience init(services: AppServices, shortcutReference: [ShortcutReferenceGroup] = []) {
        let history = services.history
        let session = services.session
        let context = SettingsContext(
            settings: services.settings,
            vault: services.vault,
            catalog: services.catalog,
            targets: services.session.library.packs.map(TargetSummary.init(pack:)),
            launchAtLogin: services.launchAtLogin,
            shortcut: ShortcutFieldModel(
                activation: services.activationShortcut,
                recorder: ShortcutRecorder(hotKeys: services.hotKeys),
                isAvailable: { [hotKeys = services.hotKeys] in hotKeys.isAvailable($0) }
            ),
            updates: services.updates,
            clearHistory: {
                do {
                    try await history.clear()
                } catch {
                    Log.logger(.store).error("Could not clear the history")
                    return false
                }
                await session.refreshRecallDrafts()
                return true
            }
        )
        self.init(
            context: context,
            model: SettingsWindowModel(config: services.config, shortcutReference: shortcutReference),
            activator: services.activator
        )
    }

    init(context: SettingsContext, model: SettingsWindowModel, activator: any AppActivating) {
        self.context = context
        self.model = model
        self.activator = activator

        let hosting = NSHostingController(rootView: SettingsRootView(model: model, context: context))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty unified toolbar makes the title bar taller, so the traffic lights sit inside the
        // inset glass sidebar (macOS 26 sidebar layout) instead of across its top edge.
        window.toolbar = NSToolbar(identifier: "PromptImproverSettingsToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.setContentSize(EmberDesign.Settings.windowSize)
        window.contentMinSize = EmberDesign.Settings.windowSize
        window.contentMaxSize = EmberDesign.Settings.windowSize
        window.title = model.selectedPane.title

        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
        windowFrameAutosaveName = "PromptImproverSettingsWindow"
        followPaneTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Opens Settings in front of every other app, on `pane` (or on the pane shown last). The panel
    /// deep-links: "Open Settings" on a key or model problem opens `.engine`, and the custom
    /// instructions entry of its actions menu opens `.instructions`.
    func show(pane: SettingsPane? = nil) {
        if let pane {
            model.selectedPane = pane
        }
        guard let window else { return }
        let opening = !window.isVisible
        if opening {
            context.launchAtLogin.refresh()
            if !window.setFrameUsingName(windowFrameAutosaveName) {
                window.center()
            }
        }
        activator.activate()
        window.makeKeyAndOrderFront(nil)
        if opening {
            // Nothing starts focused: AppKit would otherwise put the caret in the first text
            // field (a model id, an API key) and select its text.
            window.makeFirstResponder(nil)
        }
    }

    /// Ends a recording in progress and drops the dialog, so neither is waiting when the window
    /// opens again.
    func windowWillClose(_ notification: Notification) {
        context.shortcut.recorder.cancel()
        model.dialog = nil
    }

    /// Keeps the window title on the pane's name, for the Window menu and VoiceOver.
    private func followPaneTitle() {
        withObservationTracking {
            window?.title = model.selectedPane.title
        } onChange: { [weak self] in
            Task { @MainActor in self?.followPaneTitle() }
        }
    }
}
