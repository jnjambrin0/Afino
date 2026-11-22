import Foundation
import ServiceManagement

/// What the system says of Afino's login item registration.
nonisolated enum LoginItemStatus: Sendable, Equatable {
    case enabled
    /// Registered, but the user turned it off in System Settings › General › Login Items, or has
    /// yet to approve it there: Afino will not open at login until they do.
    case requiresApproval
    case notRegistered
    /// The system cannot find the app to register: it runs from somewhere it does not accept,
    /// such as a disk image.
    case notFound
}

/// "Open at login", as the system keeps it. A protocol so the model can be tested without
/// registering anything.
protocol LoginItemServicing {
    var status: LoginItemStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
    /// Opens System Settings › General › Login Items, where the user approves or allows what
    /// macOS blocks.
    func openSystemSettings()
}

/// "Open at login": Afino registered with the system as a login item. The system holds
/// the state; there is no setting for it.
struct LoginItemService: LoginItemServicing {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp
        if isEnabled {
            // Registering again refreshes a registration left by a previous copy of the app.
            if service.status == .enabled {
                try? service.unregister()
            }
            try service.register()
        } else {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
