import AppKit
import os
import PICore
import PIDesign
import PIFoundation
import PIPrompts
import PIProviders
import SwiftUI

/// Why the panel went away.
enum PanelDismissReason: String, Sendable {
    case escape
    case toggle
    /// ⌘W, or anything else that asks the window to close.
    case closeCommand
    case outsideClick
    /// A click in another of this app's windows, such as the menu bar item.
    case localInteraction
    case appDeactivated
    /// Copy & Close: the keyboard was handed back before the "Copied" pill played.
    case copiedAndClosed

    /// Esc, the shortcut and ⌘W hand the keyboard back to the app that had it. A click elsewhere
    /// or another app becoming active has already chosen where the keyboard goes; restoring the
    /// previous app then would fight the user. Copy & Close restored it before its confirmation.
    var restoresPreviousApplication: Bool {
        switch self {
        case .escape, .toggle, .closeCommand: true
        case .outsideClick, .localInteraction, .appDeactivated, .copiedAndClosed: false
        }
    }
}

/// What the panel needs from the rest of the app, handed in by the composition root.
struct PanelDependencies {
    var session: ImproveSession
    var settings: SettingsModel
    var vault: CredentialVault
    /// Nil when there is no history store (the ⌘Y list is then never offered).
    var history: HistoryStore?
    /// Opens Settings, on a given pane when there is an obvious one (a key error opens Engine).
    /// The panel closes itself first.
    var openSettings: (SettingsPane?) -> Void
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Read only when the user clicks Paste or presses ⌘V in the add-a-key card.
    var readClipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    /// For a selection copied with ⌘C and for "Copy Details" (the prompt itself goes through the
    /// session, which keeps track of what is on the clipboard).
    var writeClipboard: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Shows and hides the panel and runs everything in it. The panel and its whole view tree are made
/// once, at launch, and warmed with one invisible paint (`prewarm()`); showing it is then placing,
/// activating and fading in. Hiding always goes: give the keyboard back → fade → `orderOut` →
/// `session.panelDidClose()`.
///
/// The session (`ImproveSession`) is the single source of truth for the prompt; this controller
/// reads it, calls its methods and keeps only the panel's own state (`PanelModel`). Every key goes
/// through `PanelKeyMap` first; every height change through `PanelHeightAnimator`.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: PromptPanel
    /// The compose input: an AppKit view laid over the SwiftUI content and never removed from the
    /// window, so it can take the keyboard synchronously on every show.
    let input: ComposeInputView
    let model = PanelModel()
    let streamView: StreamTextView
    let refineField: PanelTextField
    let keyField: PanelSecureField
    let filterField: PanelTextField
    var onDismiss: ((PanelDismissReason) -> Void)?
    /// Called each time the panel is shown (the menu bar item clears its attention dot).
    var onPresent: (() -> Void)?

    let session: ImproveSession
    let settings: SettingsModel
    let vault: CredentialVault
    var library: TargetPackLibrary { session.library }

    private(set) var isPresented = false
    let dependencies: PanelDependencies
    let container: PanelContainerView
    let surface: PanelGlassSurfaceView
    private let hostingView: NSHostingView<AnyView>
    private let activator: any AppActivating
    private let focusHandoff: any FocusHandling
    let log = Log.logger(.panel)
    private let showMetrics = PanelShowMetrics()
    let shrinkAnimator = PanelShrinkAnimator()
    let cardWindow = PanelFloatingCardWindow()
    private(set) var heightAnimator: PanelHeightAnimator?
    /// Bumped on every show and hide, so a finishing hide fade (or the prewarm paint) never hides
    /// a panel that was presented again in the meantime.
    var visibilityGeneration = 0
    private(set) var anchor: PanelAnchor?
    private var hasPrewarmed = false
    private var prewarmProbe: FrameProbe?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignActiveObserver: (any NSObjectProtocol)?

    // Session tracking (PanelController+Session).
    var lastState: SessionState?
    var lastScreen: PanelScreen?
    var trackedRunID: Int?
    var runHasShownText = false
    /// The well's content height last reported by the result text.
    var wellContentHeight: CGFloat = 0
    var pendingFocus: PanelFocus?
    var setupTask: Task<Void, Never>?
    var toastTask: Task<Void, Never>?
    var historyTask: Task<Void, Never>?
    var confirmationTask: Task<Void, Never>?

    init(dependencies: PanelDependencies, activator: any AppActivating, focusHandoff: any FocusHandling = FocusHandoff()) {
        self.dependencies = dependencies
        session = dependencies.session
        settings = dependencies.settings
        vault = dependencies.vault
        self.activator = activator
        self.focusHandoff = focusHandoff

        let inset = EmberDesign.Panel.contentInset
        let width = EmberDesign.Panel.width
        input = ComposeInputView(placeholder: PanelStrings.composePlaceholder)
        streamView = StreamTextView(frame: CGRect(x: 0, y: 0, width: width - 2 * inset, height: EmberDesign.Panel.wellMinHeight))
        refineField = PanelTextField(
            placeholder: PanelStrings.refinePlaceholder,
            font: .preferredFont(forTextStyle: .body),
            identifier: PanelAccessibilityID.refineField)
        keyField = PanelSecureField(identifier: PanelAccessibilityID.setupKeyField)
        filterField = PanelTextField(
            placeholder: PanelStrings.historyFilterPlaceholder,
            font: .preferredFont(forTextStyle: .title3),
            identifier: PanelAccessibilityID.historyFilter)

        let size = CGSize(width: width, height: EmberDesign.Panel.composeHeight)
        panel = PromptPanel(contentRect: CGRect(origin: .zero, size: size))
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        // The panel owns its size (placement, the state's height); the SwiftUI content must not
        // push its ideal size onto the window.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        // A hosting view used directly as a content view resets the window's minimum size to
        // zero on its first layout, even with `sizingOptions` empty. Inside a plain container it
        // cannot; the container is what the glass holds.
        container = PanelContainerView(frame: CGRect(origin: .zero, size: size))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        // The input fills what the footer leaves (`layoutInput`). Its height is set by hand on
        // every resize rather than by a flexible autoresizing mask: that mask becomes a required
        // constraint that would stop the window from shrinking into the "Copied" pill.
        input.autoresizingMask = [.width, .minYMargin]
        container.addSubview(input)
        surface = PanelGlassSurfaceView(frame: CGRect(origin: .zero, size: size), content: container)
        panel.contentView = surface
        panel.invalidateShadow()
        super.init()

        layoutInput()
        hostingView.rootView = AnyView(PanelRootView(controller: self))
        let animator = PanelHeightAnimator { [weak self] height in self?.applyHeight(height) }
        // The panel's screen drives the frames; the shadow follows the glass once a change settles.
        animator.window = panel
        animator.onSettle = { [weak self] in self?.panel.invalidateShadow() }
        heightAnimator = animator
        panel.delegate = self
        panel.onCloseRequest = { [weak self] in self?.dismiss(.closeCommand) }
        configureViews()
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidResignActive() }
        }
        startObservingSession()
    }

    isolated deinit {
        removeEventMonitors()
        if let resignActiveObserver { NotificationCenter.default.removeObserver(resignActiveObserver) }
    }

    private func configureViews() {
        input.onPreferredHeightChange = { [weak self] old, new in
            guard let self, screen == .compose else { return }
            updateHeight(.input(old: old, new: new))
        }
        input.onDraftChange = { [weak self] text in
            guard let self else { return }
            model.showsRecalledDraft = false
            session.setDraft(text)
        }
        input.onSubmit = { [weak self] _ in self?.perform(.primary) }
        input.onMoveToWindow = { [weak self] in self?.applyPendingFocus() }
        input.setDraft(session.state.draft)

        streamView.setAccessibilityLabel(PanelStrings.resultAccessibilityLabel)
        streamView.setAccessibilityIdentifier(PanelAccessibilityID.result)
        streamView.onContentHeightChange = { [weak self] height in
            guard let self else { return }
            wellContentHeight = height
            updateHeight(.content)
        }

        refineField.onTextChange = { [weak self] text in self?.model.refineText = text }
        refineField.onMoveToWindow = { [weak self] in self?.applyPendingFocus() }
        keyField.onTextChange = { [weak self] text in
            guard let self else { return }
            model.setupKeyText = text
            if !model.setupStatus.holdsCard { model.setupStatus = .idle }
        }
        keyField.onMoveToWindow = { [weak self] in self?.applyPendingFocus() }
        keyField.onFocusChange = { [weak self] focused in self?.model.isKeyFieldFocused = focused }
        keyField.setPlaceholder(PanelStrings.keyPlaceholder(settings.provider.displayName))
        filterField.onTextChange = { [weak self] text in self?.historyFilterDidChange(text) }
        filterField.onMoveToWindow = { [weak self] in self?.applyPendingFocus() }
    }

    // MARK: Prewarm

    /// Lays the panel out at its target frame and paints it once while invisible — no key, no
    /// clicks — so the glass, the fonts and TextKit are warm for the first show. Once only.
    func prewarm() {
        guard !hasPrewarmed, !isPresented else { return }
        hasPrewarmed = true
        let start = ProcessInfo.processInfo.systemUptime
        let anchor = PanelPlacement.anchor(on: targetScreen())
        self.anchor = anchor
        refreshFromSession()
        PanelMotion.setFrameImmediately(panel, anchor.frame(height: desiredHeight()))
        surface.layoutSubtreeIfNeeded()
        input.prewarm()
        PanelMotion.setFrameImmediately(panel, anchor.frame(height: desiredHeight()))

        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        let generation = visibilityGeneration
        // Ordered out once a frame has been composited with it (the second display frame).
        prewarmProbe = FrameProbe(screen: panel.screen ?? NSScreen.main, frames: 2) { [weak self] frameTime in
            guard let self else { return }
            prewarmProbe = nil
            // A show that started meanwhile owns the panel now.
            guard visibilityGeneration == generation, !isPresented else { return }
            panel.orderOut(nil)
            resetAppearance()
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            log.notice("""
                Panel prewarmed in \(elapsed, format: .fixed(precision: 1), privacy: .public) ms \
                (\(frameTime == nil ? "no display frame seen" : "first paint composited", privacy: .public))
                """)
        }
    }

    // MARK: Showing and hiding

    /// The shortcut: a panel that is still fading out counts as closed, so the shortcut reopens
    /// it instead of dismissing it a second time.
    ///
    /// - Parameter pressedAt: When the shortcut's key went down (system uptime), for the latency.
    func toggle(pressedAt: TimeInterval? = nil) {
        if isPresented {
            dismiss(.toggle)
        } else {
            present(pressedAt: pressedAt)
        }
    }

    /// Shows the panel on the screen under the pointer, with the keyboard already in the field
    /// the screen calls for. While it is up, brings it forward instead.
    ///
    /// - Parameter pressedAt: When the shortcut's key went down (system uptime), for the latency.
    func present(pressedAt: TimeInterval? = nil) {
        guard !isPresented else {
            // Already up (the menu bar, a second launch): bring it forward with the keyboard.
            activator.activate()
            panel.makeKeyAndOrderFront(nil)
            pendingFocus = focusTarget(for: screen)
            applyPendingFocus()
            return
        }
        showMetrics.begin()
        prewarmProbe?.cancel()
        prewarmProbe = nil

        let anchor = PanelPlacement.anchor(on: targetScreen())
        self.anchor = anchor
        focusHandoff.captureCurrentFrontmostApplication()
        prepareForPresentation()
        model.isFullKeyboardAccessEnabled = NSApp.isFullKeyboardAccessEnabled
        refreshFromSession()
        isPresented = true
        let height = desiredHeight()
        heightAnimator?.setHeight(height, transition: .instant)
        PanelMotion.setFrameImmediately(panel, anchor.frame(height: height))
        container.layoutSubtreeIfNeeded()
        // The text view has the keyboard before the panel is even on screen, so the first
        // keystroke after the shortcut lands in it.
        pendingFocus = focusTarget(for: screen)
        applyPendingFocus()
        activator.activate()
        panel.makeKeyAndOrderFront(nil)
        PanelMotion.appear(panel, surface: surface, reduceMotion: reduceMotion)
        installEventMonitors()
        showMetrics.panelOrderedIn(on: panel.screen ?? NSScreen.main, pressedAt: pressedAt)
        logFocusSoon()
        onPresent?()
    }

    /// Hides the panel: gives the keyboard back when `reason` calls for it, then fades out.
    func dismiss(_ reason: PanelDismissReason) {
        guard isPresented else { return }
        isPresented = false
        removeEventMonitors()
        showMetrics.cancel()
        closeMenu(animated: false)

        if reason.restoresPreviousApplication {
            // Request the activation handoff before hiding the key panel. Hiding first can let
            // AppKit promote a fallback app (usually Finder), after which cooperative activation
            // is no longer guaranteed.
            focusHandoff.restorePreviousApplicationIfPossible()
        } else if reason != .copiedAndClosed {
            focusHandoff.clear()
        }

        visibilityGeneration += 1
        let generation = visibilityGeneration
        // While the fade runs the window is still on screen, but the panel counts as closed.
        PanelMotion.hide(panel) { [weak self] in
            guard let self, visibilityGeneration == generation else { return }
            panel.orderOut(nil)
            resetAppearance()
            // Only once the panel is off screen, so the content never visibly resets while it fades.
            panelDidHide()
        }
        log.info("Panel dismissed [reason=\(reason.rawValue, privacy: .public)]")
        onDismiss?(reason)
    }

    /// The panel is off screen: the session ends a finished prompt (a run in flight carries on),
    /// and the panel forgets what belonged to this showing.
    private func panelDidHide() {
        model.isConfirmingCopy = false
        model.resetTransientState()
        model.isOriginalExpanded = false
        model.headerHeight = EmberDesign.Panel.headerHeight
        session.panelDidClose()
        refreshFromSession()
    }

    /// Hands the keyboard back to the app that had it, without hiding the panel (Copy & Close
    /// does this before its confirmation plays).
    func restorePreviousApplication() {
        focusHandoff.restorePreviousApplicationIfPossible()
    }

    /// Cancels a hide fade, a confirmation or a prewarm paint in flight and restores full opacity.
    private func prepareForPresentation() {
        visibilityGeneration += 1
        confirmationTask?.cancel()
        confirmationTask = nil
        if model.isConfirmingCopy {
            model.isConfirmingCopy = false
        }
        resetAppearance()
    }

    /// Full opacity, clicks on, the window's corner radius, no animation in flight.
    func resetAppearance() {
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        shrinkAnimator.cancel()
        surface.setCornerRadius(EmberDesign.Radius.window)
        PanelMotion.cancelAppear(surface: surface)
        panel.invalidateShadow()
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: Size

    /// What made the panel's height change; it decides the transition.
    enum HeightChange {
        /// The screen changed (submit, completion, a card): a spring.
        case screen
        /// The well's text grew or changed.
        case content
        /// The compose input grew or shrank.
        case input(old: CGFloat, new: CGFloat)
        /// The original was expanded or collapsed.
        case header
        /// The history list's row count changed (filtering).
        case list
    }

    /// The height the panel's current state asks for.
    func desiredHeight() -> CGFloat {
        let screen = screen
        let problem = problemPresentation(at: Date())
        let showsBlock = problem?.placement == .block
        return PanelPresentation.height(PanelHeightInput(
            screen: screen,
            inputHeight: input.preferredHeight,
            headerHeight: model.headerHeight,
            contentHeight: showsBlock ? 0 : wellContentHeight,
            showsNotice: problem?.placement == .notice,
            historyRows: model.history.isLoaded ? model.history.visible.count : 0,
            maxHeight: anchor?.maxHeight ?? EmberDesign.Panel.maxHeightCap))
    }

    /// Every height change goes through the animator: one line at once, a paste with a short
    /// ease, submit and completion on a spring, streaming text followed (growing only). Under
    /// Reduce Motion every change is immediate.
    func updateHeight(_ change: HeightChange) {
        guard isPresented, !model.isConfirmingCopy, let heightAnimator else { return }
        let transition: PanelHeightAnimator.Transition
        switch change {
        case .list:
            transition = .instant
        case .screen:
            transition = .spring
        case .content:
            transition = screen == .running ? .follow : .spring
        case .input(let old, let new):
            transition = abs(new - old) <= input.oneLineHeight + 0.5 ? .instant : .ease(duration: PanelLayout.pasteResizeDuration)
        case .header:
            transition = .ease(duration: PanelLayout.originToggleDuration)
        }
        heightAnimator.setHeight(desiredHeight(), transition: reduceMotion ? .instant : transition)
    }

    /// Sets the panel's height; the top edge stays where it is.
    private func applyHeight(_ height: CGFloat) {
        guard let anchor else { return }
        let frame = anchor.frame(height: height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    // The native shadow is cached per frame; the glass shape follows the window.
    func windowDidResize(_ notification: Notification) {
        layoutInput()
        panel.invalidateShadow()
        repositionMenu()
    }

    /// The compose input fills the panel above the footer (never less than one line; below that
    /// it is hidden anyway, inside the pill).
    private func layoutInput() {
        let bounds = container.bounds
        let inset = EmberDesign.Panel.contentInset
        let height = max(bounds.height - EmberDesign.Panel.footerHeight, EmberDesign.Panel.inputMinHeight)
        let frame = CGRect(x: inset, y: bounds.height - height, width: max(bounds.width - 2 * inset, 0), height: height)
        if input.frame != frame { input.frame = frame }
    }

    // MARK: Focus

    /// The view that holds the keyboard on a screen.
    enum PanelFocus {
        case input
        case refine
        case key
        case filter
        /// No text field: the container swallows stray keys.
        case container
    }

    func focusTarget(for screen: PanelScreen) -> PanelFocus {
        switch screen {
        case .compose: .input
        case .result: .refine
        case .setup: .key
        case .history: .filter
        case .running, .failed, .stopped: .container
        }
    }

    /// Gives the keyboard to the field the screen calls for, as soon as that field is in the
    /// window (a field SwiftUI has just added reports in through `onMoveToWindow`).
    func applyPendingFocus() {
        guard let target = pendingFocus, isPresented || panel.isVisible else { return }
        let responder: NSView
        switch target {
        case .input: responder = input.textView
        case .refine: responder = refineField
        case .key: responder = keyField
        case .filter: responder = filterField
        case .container: responder = container
        }
        guard responder.window === panel else { return }
        if panel.firstResponder !== responder, !isFieldEditor(of: responder) {
            panel.makeFirstResponder(responder)
        }
        pendingFocus = nil
    }

    private func isFieldEditor(of view: NSView) -> Bool {
        guard let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor else { return false }
        return editor.delegate as? NSView === view
    }

    // MARK: Event monitors

    private func installEventMonitors() {
        removeEventMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return handleLocalEvent(event)
        }
        // Pointer-only: it exists solely to close the panel when the user clicks outside Afino.
        // It sees no keyboard input, cannot change events and needs no permission.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresented, !self.model.isConfirmingCopy,
                      !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                // An input method's candidate window and Writing Tools belong to other processes:
                // a click there is part of typing, not a click away.
                if let textView = self.panel.firstResponder as? NSTextView,
                   textView.hasMarkedText() || textView.isWritingToolsActive {
                    return
                }
                self.dismiss(.outsideClick)
            }
        }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard isPresented, !model.isConfirmingCopy else { return event }
        if event.type == .keyDown {
            guard event.window === panel else { return event }
            return handleKeyDown(event)
        }
        if model.openMenu != nil {
            if event.window === cardWindow { return event }
            closeMenu(animated: true)
            // The click that closes a card does nothing else, as with a menu.
            if event.window === panel { return nil }
        }
        // A click in another of this app's windows (the menu bar item, Settings).
        if event.window !== panel, event.window !== cardWindow, !panel.frame.contains(NSEvent.mouseLocation) {
            dismiss(.localInteraction)
        }
        return event
    }

    /// Every key goes to `PanelKeyMap` first; what it does not claim reaches the focused view.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // While an input method is composing, or Writing Tools is at work, every key is theirs.
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() || textView.isWritingToolsActive {
            return event
        }
        guard let chord = KeyChord(event: event),
              let command = PanelKeyMap.command(for: chord, in: keyContext()) else { return event }
        perform(command)
        return nil
    }

    /// Another app became active (⌘Tab, a click in it, a notification): the panel goes away.
    /// Giving the keyboard back on Esc makes this app resign active too, but by then the panel
    /// is already closed and this does nothing.
    private func applicationDidResignActive() {
        // Copy & Close gives the keyboard back on purpose before its confirmation plays.
        guard isPresented, panel.isVisible, !model.isConfirmingCopy else { return }
        dismiss(.appDeactivated)
    }

    // MARK: Diagnostics

    /// Whether activation took, a moment after a show: the app active, the panel key, the text
    /// view typing.
    private func logFocusSoon() {
        let generation = visibilityGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, isPresented, visibilityGeneration == generation else { return }
            log.notice("""
                Panel focus after 250 ms: active=\(NSApp.isActive, privacy: .public) \
                key=\(self.panel.isKeyWindow, privacy: .public) \
                typing=\(self.panel.firstResponder === self.input.textView, privacy: .public)
                """)
        }
    }

    // MARK: Screens

    private func targetScreen() -> PanelScreenSnapshot {
        let screens = NSScreen.screens.map(PanelScreenSnapshot.init(screen:))
        let current = panel.screen.map(PanelPlacement.screenIdentifier(for:))
        let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return PanelPlacement.resolveTargetScreen(
            mouseLocation: NSEvent.mouseLocation,
            currentScreenIdentifier: current,
            screens: screens
        ) ?? PanelScreenSnapshot(identifier: "none", frame: fallback, visibleFrame: fallback)
    }

    /// A rectangle of the panel's content (top-left origin, as SwiftUI's global space in the
    /// hosting view) in screen coordinates.
    func screenRect(fromContent rect: CGRect) -> CGRect {
        let frame = panel.frame
        return CGRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
