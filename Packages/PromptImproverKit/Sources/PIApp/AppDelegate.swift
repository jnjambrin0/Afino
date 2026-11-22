import AppKit
import Observation
import os
import PICore
import PIFoundation

/// Composition root. Builds every service once and hands dependencies down by initializer;
/// nothing in the app reaches for a shared singleton.
///
/// Launch order: one copy at a time → (Release) install location → services → main menu and
/// menu bar item → shortcut → panel → welcome (first launch) → updater. The panel is prewarmed
/// on the first idle turn of the run loop, once launching has drawn whatever it draws.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Log.logger(.app)
    private var services: AppServices?
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    private var settingsWindow: SettingsWindowController?
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await launch() }
    }

    private func launch() async {
        guard await SingleInstance.resolve() else { return }

        let config = ConfigStore()
        let activator = AppActivator()
        let installLocation = InstallLocationManager()
        #if !DEBUG
        guard await InstallLocationPrompt.run(manager: installLocation, config: config, activator: activator) else { return }
        #endif

        let services: AppServices
        do {
            services = try AppServices(config: config, activator: activator, installLocation: installLocation)
        } catch {
            // The bundled packs or engine prompt could not be read: the build itself is broken.
            log.fault("Launch failed: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        self.services = services
        services.vault.loadStoredKeys()
        Task { await services.session.refreshRecallDrafts() }
        cleanUpLegacyData(settings: services.settings)
        followAppearance(of: services.settings)

        let actions = AppMenuActions(
            showPanel: { [weak self] in self?.panel?.present() },
            showSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { services.updates.checkForUpdates() },
            canCheckForUpdates: { services.updates.canCheckForUpdates },
            showAbout: {
                activator.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        )
        NSApp.mainMenu = MainMenu.make(actions: actions)
        statusItem = StatusItemController(
            actions: actions,
            session: services.session,
            settings: services.settings,
            activationShortcut: services.activationShortcut,
            isPanelVisible: { [weak self] in self?.panel?.isPresented ?? false }
        )

        services.activationShortcut.start { [weak self] in
            // On the welcome's shortcut step, pressing it is the user trying it: the welcome
            // celebrates it instead of the panel opening.
            if self?.welcome?.handleActivationShortcut() == true { return }
            guard let panel = self?.panel else { return }
            panel.toggle(pressedAt: services.hotKeys.lastPressUptime)
        }

        var panelDependencies = PanelDependencies(
            session: services.session,
            settings: services.settings,
            vault: services.vault,
            history: services.history,
            openSettings: { [weak self] pane in self?.showSettings(pane: pane) }
        )
        #if DEBUG
        // `--demo-engine` and friends swap in a scripted engine with no network (see `PanelDemo`).
        let demo = PanelDemo(arguments: ProcessInfo.processInfo.arguments)
        if let demo {
            panelDependencies = demo.dependencies(base: panelDependencies)
        }
        #endif
        let panel = PanelController(dependencies: panelDependencies, activator: activator)
        panel.onPresent = { [weak self] in self?.statusItem?.panelDidOpen() }
        statusItem?.showHistory = { [weak panel] in panel?.presentHistory() }
        self.panel = panel
        #if DEBUG
        demo?.drive(panel, arguments: ProcessInfo.processInfo.arguments)
        #endif
        // The welcome: on the first launch, and again whenever Settings › About asks for it.
        let welcome = WelcomeWindowController(services: services) { [weak panel] in panel?.present() }
        self.welcome = welcome
        welcome.start()
        // On the first idle turn, once launching has drawn whatever it draws.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { panel.prewarm() }
        }

        services.updates.start()

        let elapsed = NSRunningApplication.current.launchDate.map { Date().timeIntervalSince($0) * 1000 } ?? -1
        log.notice("Launch: ready \(elapsed, format: .fixed(precision: 0), privacy: .public) ms after the process started")
    }

    /// Clears what versions before 1.0 left on disk (`LegacyCleanup`), once and off the main
    /// thread. Nothing the user wrote is deleted.
    private func cleanUpLegacyData(settings: SettingsModel) {
        guard !settings.legacyCleanupDone else { return }
        Task.detached(priority: .utility) {
            let succeeded = (try? LegacyCleanup().run()) != nil
            await MainActor.run {
                if succeeded { settings.legacyCleanupDone = true }
            }
        }
    }

    /// Opens Settings in front, on `pane` when given (the panel deep-links: a key error opens
    /// `.engine`). The window is made on first use and kept.
    private func showSettings(pane: SettingsPane? = nil) {
        guard let services else { return }
        let controller = settingsWindow
            ?? SettingsWindowController(services: services, shortcutReference: PanelKeyMap.referenceGroups())
        settingsWindow = controller
        controller.show(pane: pane)
    }

    /// Applies the theme chosen in Settings to the whole app, now and whenever it changes.
    private func followAppearance(of settings: SettingsModel) {
        withObservationTracking {
            NSApp.appearance = settings.appearance.appKitAppearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.followAppearance(of: settings) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening Afino again (Finder, Spotlight, a second launch handing over) shows the panel
    /// — or the welcome, while it is up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if welcome?.bringToFront() == true { return false }
        panel?.present()
        return false
    }
}
