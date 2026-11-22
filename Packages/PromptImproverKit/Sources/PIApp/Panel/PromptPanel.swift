import AppKit

/// The panel window: borderless (no title bar, Spotlight-like), neither movable nor resizable,
/// and an *activating* panel — it becomes key in an app that becomes active, so Writing Tools,
/// input methods, the Edit menu and ⌘X/C/V/Z work without being reimplemented.
///
/// Always dark, whatever the system or the Theme setting says: the panel is a dark sheet of glass
/// over whatever the user was doing, and it reads the same over a light document as over a dark
/// one. Its menus are child windows and take their appearance from it. (The Theme setting applies
/// to Settings and the app's other windows.)
///
/// Created once at launch and never recreated (`PanelController`).
final class PromptPanel: NSPanel {
    /// ⌘W (the main menu's Close) and anything else that asks the panel to close: the owner
    /// dismisses it the way Esc does instead of closing it for good.
    var onCloseRequest: (() -> Void)?
    private var contrastObserver: (any NSObjectProtocol)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            // The window and its backing store exist from launch: nothing is built on first show.
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Over full-screen apps, in whichever Space is active, out of ⌘` and Mission Control.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        level = .floating
        isMovableByWindowBackground = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        applyDarkAppearance()
        // A named appearance does not follow Increase Contrast by itself.
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDarkAppearance() }
        }
    }

    private func applyDarkAppearance() {
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        appearance = NSAppearance(named: increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        onCloseRequest?()
    }

    /// A window without a close button disables Close in the menu; this one closes all the same.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)) {
            return onCloseRequest != nil
        }
        return super.validateMenuItem(menuItem)
    }
}
