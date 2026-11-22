import AppKit
import Observation
import os
import PICore
import PIDesign
import PIFoundation
import PIPrompts
import SwiftUI

/// The welcome window: on the first launch, and again whenever `onboardingCompleted` turns false
/// (Settings › About › "Show welcome again").
///
/// A titled window with no visible title bar or buttons, always dark like the panel, one size for
/// every step, centred on the screen with the pointer. While it is up the app is a regular app
/// (a Dock icon, ⌘Tab): "Get a key" sends the user to a browser, and an accessory app's window
/// left behind there could only be found again through Mission Control. It goes back to being an
/// accessory app as the window closes.
///
/// Leaving it — Start, Skip, Esc, ⌘W — marks onboarding completed; Start then opens the panel.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    let flow: WelcomeFlow
    private let settings: SettingsModel
    private let activator: any AppActivating
    private let keyStep: WelcomeKeyStepModel
    private let shortcutStep: WelcomeShortcutStepModel
    private let context: WelcomeContext
    private let openPanel: () -> Void
    private var window: NSWindow?
    private var contrastObserver: (any NSObjectProtocol)?
    /// The app was made a regular app for this showing.
    private var promotedActivationPolicy = false
    private let log = Log.logger(.app)
    #if DEBUG
    private let debug: WelcomeDebugOptions
    private var tour: WelcomeTour?
    #endif

    /// - Parameter openPanel: Start, on the last step, opens the panel once the window is gone.
    convenience init(services: AppServices, openPanel: @escaping () -> Void) {
        #if DEBUG
        let debug = WelcomeDebugOptions(arguments: ProcessInfo.processInfo.arguments)
        debug.applyLanguage()
        let vault: any KeyVaulting = debug.isTour ? WelcomeTourVault() : services.vault
        #else
        let vault: any KeyVaulting = services.vault
        #endif
        let hotKeys = services.hotKeys
        let shortcutStep = WelcomeShortcutStepModel(
            activation: services.activationShortcut,
            config: services.config,
            field: ShortcutFieldModel(
                activation: services.activationShortcut,
                recorder: ShortcutRecorder(hotKeys: hotKeys),
                isAvailable: { hotKeys.isAvailable($0) }
            )
        )
        let packs = services.session.library.packs
        self.init(
            settings: services.settings,
            activator: services.activator,
            keyStep: WelcomeKeyStepModel(settings: services.settings, vault: vault),
            shortcutStep: shortcutStep,
            illustrationTarget: packs.first.map {
                WelcomeIllustrationTarget(name: PanelMenus.displayName(of: $0), monogram: HistoryRowFormatter.monogram(for: $0))
            } ?? WelcomeIllustrationTarget(name: "Claude", monogram: .letters("Cl")),
            targetCount: packs.count,
            openPanel: openPanel
        )
        #if DEBUG
        tour = debug.isTour ? WelcomeTour(markerDirectory: debug.tourMarkerDirectory, vault: vault as? WelcomeTourVault) : nil
        #endif
    }

    init(
        settings: SettingsModel,
        activator: any AppActivating,
        keyStep: WelcomeKeyStepModel,
        shortcutStep: WelcomeShortcutStepModel,
        illustrationTarget: WelcomeIllustrationTarget,
        targetCount: Int,
        openPanel: @escaping () -> Void
    ) {
        self.settings = settings
        self.activator = activator
        self.keyStep = keyStep
        self.shortcutStep = shortcutStep
        self.openPanel = openPanel
        let flow = WelcomeFlow(settings: settings)
        self.flow = flow
        context = WelcomeContext(
            flow: flow,
            keyStep: keyStep,
            shortcutStep: shortcutStep,
            guide: WelcomeKeyGuide.groups(targetCount: targetCount),
            illustrationTarget: illustrationTarget,
            openURL: { NSWorkspace.shared.open($0) }
        )
        #if DEBUG
        debug = WelcomeDebugOptions(arguments: ProcessInfo.processInfo.arguments)
        #endif
        super.init()
        flow.onExit = { [weak self] exit in self?.close(exit) }
        flow.onStepChange = { [weak self] old, new in self?.stepDidChange(from: old, to: new) }
    }

    isolated deinit {
        if let contrastObserver { NSWorkspace.shared.notificationCenter.removeObserver(contrastObserver) }
    }

    // MARK: Showing

    /// Shows the welcome now if onboarding is not completed, and again whenever it stops being
    /// completed. Call once, after the panel exists (Start opens it).
    func start() {
        #if DEBUG
        if let step = debug.step {
            present(at: step, activates: !debug.isTour)
            // The tour owns the window: nothing else brings it forward or closes it.
            if let tour {
                tour.run(self)
                return
            }
        }
        #endif
        followCompletion()
    }

    private func followCompletion() {
        let isCompleted = withObservationTracking {
            settings.onboardingCompleted
        } onChange: { [weak self] in
            Task { @MainActor in self?.followCompletion() }
        }
        if !isCompleted { present() }
    }

    /// - Parameter activates: Brings the app forward with the window. The debug tour does not, so
    ///   screenshots never take the keyboard from whoever is using the Mac.
    func present(at step: WelcomeStep = .welcome, activates: Bool = true) {
        guard !flow.isPresented else {
            _ = bringToFront()
            return
        }
        keyStep.reset()
        flow.present(at: step)
        let window = window ?? makeWindow()
        self.window = window
        window.title = step.title
        place(window)
        if activates {
            if NSApp.activationPolicy() != .regular {
                promotedActivationPolicy = NSApp.setActivationPolicy(.regular)
            }
            activator.activate()
            window.makeKeyAndOrderFront(nil)
        }
        // Activation is a request macOS may turn down while another app is in use; the welcome
        // must be seen all the same.
        window.orderFrontRegardless()
        log.notice("Welcome shown at step \(step.number, privacy: .public)")
    }

    /// Opening Afino again (the Dock icon, a second launch) while the welcome is up
    /// brings the welcome forward instead of opening the panel. Returns whether it did.
    func bringToFront() -> Bool {
        guard flow.isPresented, let window else { return false }
        activator.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// The activation shortcut was pressed. On the shortcut step that is the user trying it: it
    /// is celebrated in the welcome (brought forward if the user pressed it from another app)
    /// instead of opening the panel. Returns whether it was claimed; otherwise the caller toggles
    /// the panel as usual.
    func handleActivationShortcut() -> Bool {
        guard window?.isVisible == true, flow.activationShortcutPressed() else { return false }
        ShortcutRecorder.announce(OnboardingStrings.text("welcome.shortcut.success"))
        if let window, !(NSApp.isActive && window.isKeyWindow) {
            activator.activate()
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: Leaving

    private func close(_ exit: WelcomeFlow.Exit) {
        shortcutStep.cancelRecording()
        keyStep.reset()
        window?.orderOut(nil)
        if promotedActivationPolicy {
            promotedActivationPolicy = false
            NSApp.setActivationPolicy(.accessory)
        }
        log.notice("Welcome closed (\(exit == .finished ? "finished" : "skipped", privacy: .public))")
        if exit == .finished {
            openPanel()
        }
    }

    /// ⌘W: leaves the welcome as Skip does; the flow closes the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flow.skip()
        return false
    }

    private func stepDidChange(from old: WelcomeStep, to new: WelcomeStep) {
        if old == .shortcut { shortcutStep.cancelRecording() }
        if old == .apiKey { keyStep.reset() }
        window?.title = new.title
        // The step changes under VoiceOver's cursor: it says which one came in.
        ShortcutRecorder.announce(new.announcement)
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let size = OnboardingLayout.windowSize
        let hostingView = NSHostingView(rootView: WelcomeRootView(context: context))
        // The content runs under the hidden title bar and owns its size.
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        let window = WelcomeWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.onCancel = { [weak self] in self?.flow.skip() }
        window.contentView = hostingView
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentMinSize = size
        window.contentMaxSize = size
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.delegate = self
        applyDarkAppearance(to: window)
        // A named appearance does not follow Increase Contrast by itself.
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.applyDarkAppearance(to: window)
            }
        }
        return window
    }

    /// Always dark, as the panel is, in its Increase Contrast variant when that is on.
    private func applyDarkAppearance(to window: NSWindow) {
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        window.appearance = NSAppearance(named: increaseContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
    }

    /// Centred across the screen with the pointer, a little above its middle.
    private func place(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + max(visible.height - size.height, 0) * OnboardingLayout.verticalPlacement).rounded()
        ))
    }

    #if DEBUG
    /// The debug tour drives the steps and their states without the buttons.
    var tourModels: (keyStep: WelcomeKeyStepModel, shortcutStep: WelcomeShortcutStepModel) {
        (keyStep, shortcutStep)
    }
    #endif
}

/// The welcome's window. Esc reaches `cancelOperation(_:)` when nothing in the content took it
/// (the content's own Esc shortcut normally does); either way it leaves as Skip does.
final class WelcomeWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
