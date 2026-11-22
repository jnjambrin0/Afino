import Foundation
import Observation
import os
import PIFoundation
import Sparkle

/// Afino's software updates: Sparkle's standard updater and interface behind an app-owned type,
/// so no other module sees Sparkle. The composition root creates it and starts it at launch, not
/// when some window first opens, so scheduled checks run from the start. Debug builds, builds
/// without a feed or key, and copies that cannot replace themselves never start it
/// (`UpdaterSuppression`).
@Observable
final class UpdateController {
    /// Why updates are off on this run; `nil` when the updater runs.
    let suppression: UpdaterSuppression?

    /// Whether a check can start now: false while a check or an update session is under way,
    /// and always false while the updater is off.
    private(set) var canCheckForUpdates = false

    /// Checks on Sparkle's schedule. Sparkle keeps the choice in Afino's preferences; it
    /// starts on because of `SUEnableAutomaticChecks` in the Info.plist.
    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private let delegate: UpdaterDelegate
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let log = Log.logger(.updates)

    private var updater: SPUUpdater? {
        controller?.updater
    }

    /// - Parameters:
    ///   - bundle: The app bundle, whose Info.plist carries the feed and the public key.
    ///   - isDebugBuild: A Debug build never looks for updates.
    ///   - isUpdatableLocation: Whether an update could replace this copy where it is.
    ///   - activator: Brings Sparkle's window to the front when the user asked for it.
    init(bundle: Bundle = .main, isDebugBuild: Bool, isUpdatableLocation: Bool, activator: any AppActivating) {
        suppression = UpdaterSuppression.reason(
            infoDictionary: bundle.infoDictionary ?? [:],
            isDebugBuild: isDebugBuild,
            isUpdatableLocation: isUpdatableLocation
        )
        delegate = UpdaterDelegate(activator: activator)
    }

    /// Starts the updater, which from then on checks on its schedule; the first check of a new
    /// installation happens at once. Calling it again does nothing.
    func start() {
        guard controller == nil else { return }
        if let suppression {
            log.notice("Updates are off on this run: \(String(describing: suppression), privacy: .public)")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: delegate
        )
        self.controller = controller
        observe(controller.updater)
        log.notice("Updater started")
    }

    /// "Check for Updates…": Sparkle's window comes to the front with the progress and then the
    /// result. Does nothing while `canCheckForUpdates` is false.
    func checkForUpdates() {
        guard let controller, canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    /// Keeps the observable properties in step with the updater, whose properties are
    /// KVO-compliant and change on the main thread.
    private func observe(_ updater: SPUUpdater) {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.update(from: updater) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.update(from: updater) }
            },
        ]
    }

    /// Assigns only what changed, so observers are not woken up for nothing and the setters do
    /// not write the value back.
    private func update(from updater: SPUUpdater) {
        if canCheckForUpdates != updater.canCheckForUpdates {
            canCheckForUpdates = updater.canCheckForUpdates
        }
        if automaticallyChecksForUpdates != updater.automaticallyChecksForUpdates {
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        }
    }
}
