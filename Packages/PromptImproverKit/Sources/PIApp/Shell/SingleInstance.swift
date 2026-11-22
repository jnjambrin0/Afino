import AppKit
import os
import PIFoundation

/// One copy of Afino at a time: two would fight over the shortcut and the menu bar.
/// The development build (`….PromptImprover.dev`) has its own bundle identifier and does not count.
///
/// Decided by running applications rather than `LSMultipleInstancesProhibited`, which would also
/// stop a copy that moved itself to Applications from opening its replacement.
@MainActor
enum SingleInstance {
    /// How long another copy that is on its way out gets to quit: one that moved itself to the
    /// Applications folder opens the new copy and only then quits.
    private static let quitWait: Duration = .seconds(3)
    private static let pollInterval: Duration = .milliseconds(100)

    /// Whether this copy goes on starting. When it does not, the copy that stays has been opened
    /// again (which shows its panel) and this one is quitting.
    static func resolve() async -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return true }
        let me = ProcessInfo.processInfo.processIdentifier
        func others() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != me && !$0.isTerminated }
        }
        guard !others().isEmpty else { return true }

        let log = Log.logger(.app)
        log.notice("Launch: another copy is running (pid \(others().map(\.processIdentifier), privacy: .public)); waiting for it to quit")
        let deadline = ContinuousClock.now + quitWait
        while !others().isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
        guard let survivor = others().first else {
            log.notice("Launch: the other copy quit")
            return true
        }

        log.notice("Launch: handing over to the copy that is running (pid \(survivor.processIdentifier, privacy: .public)) and quitting")
        if let url = survivor.bundleURL {
            // Opening the running copy again sends it a reopen event: it shows its panel.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        NSApp.terminate(nil)
        return false
    }
}
