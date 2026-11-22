import AppKit
import os
import PIFoundation

/// Remembers which app was in front when the panel appeared, and gives it the keyboard back
/// when the panel goes away.
@MainActor
protocol FocusHandling: AnyObject {
    @discardableResult
    func captureCurrentFrontmostApplication() -> NSRunningApplication?

    func restorePreviousApplicationIfPossible()
    /// Forgets the captured app without activating it.
    func clear()
}

/// The live `FocusHandling`: captures `NSWorkspace`'s frontmost app on show and hands activation
/// back to it with cooperative activation on dismissal.
@MainActor
final class FocusHandoff: FocusHandling {
    private static let activationRetryDelays: [Duration] = [
        .milliseconds(50),
        .milliseconds(150),
    ]

    private var previousApplication: NSRunningApplication?
    private let log = Log.logger(.panel)

    @discardableResult
    func captureCurrentFrontmostApplication() -> NSRunningApplication? {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != currentProcessIdentifier else {
            previousApplication = nil
            return nil
        }

        previousApplication = application
        return application
    }

    func restorePreviousApplicationIfPossible() {
        guard let previousApplication else {
            return
        }

        self.previousApplication = nil

        guard previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        // Cooperative activation (macOS 14+): this app hands activation over, then the other
        // app is asked to activate on its behalf.
        NSApp.yieldActivation(to: previousApplication)

        let restored = previousApplication.activate(from: .current)
        if !restored {
            log.error(
                "Failed to reactivate previous application [bundleIdentifier=\(previousApplication.bundleIdentifier ?? "unknown", privacy: .private), pid=\(previousApplication.processIdentifier, privacy: .private)]"
            )
            return
        }

        // Mouse-driven dismissals can race with the click event that activated this app. Retry
        // briefly only while this app is still frontmost, so a user-initiated switch to another
        // app is not overridden.
        Task { @MainActor [previousApplication, log] in
            for delay in Self.activationRetryDelays {
                try? await Task.sleep(for: delay)

                let frontmostApplication = NSWorkspace.shared.frontmostApplication
                guard frontmostApplication?.processIdentifier != previousApplication.processIdentifier else {
                    return
                }

                let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
                guard frontmostApplication == nil ||
                    frontmostApplication?.processIdentifier == currentProcessIdentifier else {
                    return
                }

                let retried = previousApplication.activate(from: .current)
                if !retried {
                    log.error(
                        "Retry reactivation failed [bundleIdentifier=\(previousApplication.bundleIdentifier ?? "unknown", privacy: .private), pid=\(previousApplication.processIdentifier, privacy: .private)]"
                    )
                    return
                }
            }
        }
    }

    func clear() {
        previousApplication = nil
    }
}
