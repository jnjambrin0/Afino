import AppKit
import os
import PIFoundation

extension ConfigKey where Value == String {
    /// The build (`CFBundleVersion`) for which the user chose to keep the app where it is: they
    /// are not asked again until another build.
    nonisolated static var installMoveDeclinedBuild: ConfigKey<String> { ConfigKey("installMoveDeclinedBuild", default: "") }
}

/// Release builds only, right after the single-instance check: a copy outside Applications (a
/// disk image, Downloads, translocated) cannot update itself, so it offers — once per build — to
/// move itself there and relaunch. Debug builds never ask.
@MainActor
enum InstallLocationPrompt {
    /// Whether this copy goes on starting: false when it moved, opened the moved copy and is
    /// quitting.
    static func run(
        manager: any InstallLocationManaging,
        config: ConfigStore,
        activator: any AppActivating,
        bundle: Bundle = .main
    ) async -> Bool {
        guard case .notInApplications = manager.evaluateInstallState() else { return true }
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        guard config.value(for: .installMoveDeclinedBuild) != build else { return true }

        let alert = NSAlert()
        alert.messageText = AppStrings.moveTitle
        alert.informativeText = AppStrings.moveMessage
        alert.addButton(withTitle: AppStrings.moveConfirm)
        alert.addButton(withTitle: AppStrings.moveLater)
        activator.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            config.set(build, for: .installMoveDeclinedBuild)
            return true
        }

        do {
            // Copies the app, opens the copy and terminates this one.
            _ = try await manager.moveAndRelaunchIfNeeded()
            return false
        } catch {
            Log.logger(.updates).error("Move to Applications failed: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = AppStrings.moveFailedTitle
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: AppStrings.ok)
            activator.activate()
            failure.runModal()
            return true
        }
    }
}
