import Foundation
import Observation
import os
import PIFoundation

/// "Open at login" for Settings: what the system says, and the last thing that went wrong.
/// The system has no notification for changes made in System Settings, so the owner calls
/// `refresh()` when the setting comes into view.
@Observable
final class LaunchAtLoginModel {
    /// Afino opens at login.
    private(set) var isEnabled = false
    /// Registered but waiting for the user in System Settings › General › Login Items.
    private(set) var requiresApproval = false
    /// The last change that failed, for the setting to show; cleared by the next change.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemServicing
    @ObservationIgnored private let log = Log.logger(.app)

    init(service: any LoginItemServicing) {
        self.service = service
        refresh()
    }

    /// Reads the registration again from the system.
    func refresh() {
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    /// Registers or unregisters the app, then reads back what the system made of it.
    func setEnabled(_ enabled: Bool) {
        do {
            try service.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            log.error("Open at login could not be turned \(enabled ? "on" : "off", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
