import AppKit
import os
import PIFoundation
import Sparkle

/// Sparkle's delegate for both the updater and its standard interface. It declares support for
/// Sparkle's gentle scheduled update reminders, which a background app needs: Sparkle then shows
/// an update found by a scheduled check without taking focus from the active app, except right
/// after launch. It also logs failures.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let activator: any AppActivating
    private let log = Log.logger(.updates)

    init(activator: any AppActivating) {
        self.activator = activator
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Afino is a menu bar app: an update the user asked for must come to the front
        // over whichever app is active.
        guard handleShowingUpdate, state.userInitiated else { return }
        activator.activate()
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        log.error("Update aborted: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        log.error("Could not download \(item.displayVersionString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        log.info("No update: \(error.localizedDescription, privacy: .public)")
    }
}
