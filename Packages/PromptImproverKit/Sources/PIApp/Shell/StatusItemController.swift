import AppKit
import Observation
import PICore
import PIDesign

/// The menu bar item: the app's template glyph, which follows the session (breathing while a run
/// is in flight, a checkmark when one finished with the panel hidden, a dot when something needs
/// the user), and a standard system menu.
///
/// It watches the session, the history setting and the activation shortcut with
/// `withObservationTracking`; nothing polls. The composition root tells it whether the panel is
/// on screen (`isPanelVisible`) and calls `panelDidOpen()` whenever the panel opens.
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Shows the history; the "History…" row appears only while it is set and history is on.
    var showHistory: (() -> Void)? {
        didSet { rebuildMenu() }
    }

    /// The text of the last completed improvement, for "Copy Last Result".
    private(set) var lastResult: String?
    /// What the icon shows now.
    private(set) var iconState: StatusIconState = .idle

    private let statusItem: NSStatusItem
    private let actions: AppMenuActions
    private let session: ImproveSession
    private let settings: SettingsModel
    private let activationShortcut: ActivationShortcut
    private let clipboard: any ClipboardWriting
    private let isPanelVisible: () -> Bool
    /// The system's own menu, rebuilt each time it is about to open.
    private let menu = NSMenu()

    private var tracker = StatusIconTracker()
    private var lastPhase: SessionState.Phase
    private var doneTimer: Task<Void, Never>?
    private var renderedAppearance: StatusIconAppearance?
    private var reduceMotionObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - isPanelVisible: Whether the panel is on screen now.
    ///   - showHistory: Shows the history list; nil leaves "History…" out.
    init(
        actions: AppMenuActions,
        session: ImproveSession,
        settings: SettingsModel,
        activationShortcut: ActivationShortcut,
        clipboard: any ClipboardWriting = SystemClipboard(),
        isPanelVisible: @escaping () -> Bool,
        showHistory: (() -> Void)? = nil
    ) {
        self.actions = actions
        self.session = session
        self.settings = settings
        self.activationShortcut = activationShortcut
        self.clipboard = clipboard
        self.isPanelVisible = isPanelVisible
        self.showHistory = showHistory
        lastPhase = session.state.phase
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.wantsLayer = true
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(force: true) }
        }
        observeSession()
        update()
        #if DEBUG
        Task { @MainActor [weak self] in
            // Once the menu bar has placed the item, so a click lands where a real one would.
            try? await Task.sleep(for: .seconds(1))
            self?.performDebugLaunchRequests()
        }
        #endif
    }

    #if DEBUG
    /// Debug builds only: launch flags that open a window without touching the mouse, for
    /// screenshots and quick visual checks. `--open-settings` opens Settings and
    /// `--open-status-menu` opens this item's menu as a click would, a second after launch.
    /// Pass them through `scripts/run.sh`, for example `scripts/run.sh --open-status-menu`.
    private func performDebugLaunchRequests() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--open-settings") { actions.showSettings() }
        if arguments.contains("--open-status-menu") { statusItem.button?.performClick(nil) }
    }
    #endif

    isolated deinit {
        doneTimer?.cancel()
        if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Where the item is on screen (AppKit coordinates), for tests that look at it.
    var buttonFrameOnScreen: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// The panel came on screen: whatever the icon was pointing at has been seen.
    func panelDidOpen() {
        tracker.panelDidOpen()
        doneTimer?.cancel()
        update()
    }

    // MARK: Following the session

    /// Registers for the next change of what the icon and the menu show. Observation fires once,
    /// so each change registers again.
    private func observeSession() {
        withObservationTracking {
            _ = session.state.phase
            _ = session.hasUsableKey
            _ = settings.historyEnabled
            _ = activationShortcut.registered
        } onChange: { [weak self] in
            // Called before the change lands; read the new values on the next turn.
            Task { @MainActor in
                self?.observeSession()
                self?.sessionChanged()
            }
        }
    }

    private func sessionChanged() {
        let phase = session.state.phase
        guard phase != lastPhase else {
            update()
            return
        }
        let old = lastPhase
        lastPhase = phase
        if case .running = old, phase == .result, let text = session.state.shown?.text, !text.isEmpty {
            lastResult = text
        }
        if tracker.phaseChanged(from: old, to: phase, isPanelVisible: isPanelVisible()) {
            startDoneTimer()
        }
        update()
    }

    private func startDoneTimer() {
        doneTimer?.cancel()
        doneTimer = Task { [weak self] in
            try? await Task.sleep(for: StatusIconRenderer.Metrics.doneDuration)
            guard !Task.isCancelled, let self else { return }
            tracker.doneExpired()
            update()
        }
    }

    private func update() {
        // The panel can open without telling (a caller that skips `panelDidOpen()`): anything
        // seen in it no longer needs attention.
        if isPanelVisible(), tracker != StatusIconTracker() {
            tracker.panelDidOpen()
        }
        iconState = tracker.state(phase: session.state.phase, hasUsableKey: session.hasUsableKey)
        render(force: false)
        rebuildMenu()
    }

    // MARK: Drawing

    private func render(force: Bool) {
        guard let button = statusItem.button else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let appearance = StatusIconAppearance(iconState, reduceMotion: reduceMotion)
        guard force || appearance != renderedAppearance else { return }
        renderedAppearance = appearance

        let description = Self.description(of: iconState)
        button.image = StatusIconRenderer.image(for: appearance, accessibilityDescription: description)
        button.toolTip = description
        button.setAccessibilityLabel(AppStrings.statusItemDescription)
        button.setAccessibilityValue(iconState == .idle ? nil : description)

        let key = "breathe"
        if appearance.breathes {
            if button.layer?.animation(forKey: key) == nil {
                button.layer?.add(StatusIconRenderer.breathingAnimation(), forKey: key)
            }
        } else {
            button.layer?.removeAnimation(forKey: key)
        }
    }

    private static func description(of state: StatusIconState) -> String {
        switch state {
        case .idle: AppStrings.statusItemDescription
        case .running: SettingsStrings.text("status.tooltip.running")
        case .done: SettingsStrings.text("status.tooltip.done")
        case .attention(.runFailed): SettingsStrings.text("status.tooltip.failed")
        case .attention(.noUsableKey): SettingsStrings.text("status.tooltip.noKey")
        }
    }

    // MARK: The menu

    private var menuContext: StatusMenuContext {
        StatusMenuContext(
            isRunning: session.state.isRunning,
            hasLastResult: lastResult != nil,
            canShowHistory: settings.historyEnabled && showHistory != nil,
            canCheckForUpdates: actions.canCheckForUpdates(),
            shortcutCaps: activationShortcut.registered?.keyCaps ?? []
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// Fills the system menu from `StatusMenuItems`: a separator between sections, the standard
    /// symbols, and real key equivalents (the global shortcut on "Improve a Prompt…").
    private func rebuildMenu() {
        menu.removeAllItems()
        var section: Int?
        for entry in StatusMenuItems.items(for: menuContext) {
            if let section, section != entry.section {
                menu.addItem(.separator())
            }
            section = entry.section
            let item = NSMenuItem(title: entry.title, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.isEnabled = entry.isEnabled
            if let symbol = entry.symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            if entry.id == StatusMenuCommand.improve.rawValue, let shortcut = activationShortcut.registered {
                StatusMenuKeyEquivalent.apply(caps: shortcut.keyCaps, to: item)
            } else if let chord = entry.shortcut {
                StatusMenuKeyEquivalent.apply(caps: ShortcutGlyphFormatter.caps(for: chord), to: item)
            }
            menu.addItem(item)
        }
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        perform(id)
    }

    private func perform(_ id: String) {
        switch StatusMenuCommand(rawValue: id) {
        case .improve: actions.showPanel()
        case .stop: session.stop()
        case .copyLastResult: lastResult.map(clipboard.write)
        case .history: showHistory?()
        case .settings: actions.showSettings()
        case .checkForUpdates: actions.checkForUpdates()
        case .about: actions.showAbout()
        case .quit: NSApp.terminate(nil)
        case nil: break
        }
    }
}
