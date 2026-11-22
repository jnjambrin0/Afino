import AppKit
import os
import PIFoundation

/// The one place Afino asks to become the active app: the panel on the shortcut, the
/// menu bar and a second launch; the About panel; Sparkle's update window; launch alerts.
/// Keeping the call behind this seam is what lets the activation strategy change in one place.
@MainActor
protocol AppActivating: AnyObject {
    func activate()
}

/// Activation for an accessory (`LSUIElement`) app summoned from anywhere.
///
/// Plain `NSApp.activate()` (cooperative activation, macOS 14+) is asked first. macOS may decline
/// it for an accessory app summoned from a global shortcut or a menu bar menu, so when the app is
/// still not active `fallbackDelay` later, the deprecated `activate(ignoringOtherApps:)` follows:
/// the only call to it in the app. Each activation logs which of the two took effect, which shows
/// in Console whether the fallback is still needed.
@MainActor
final class AppActivator: AppActivating {
    /// Shorter than a typist's reaction time after releasing the shortcut.
    private static let fallbackDelay: Duration = .milliseconds(50)
    private static let pollInterval: Duration = .milliseconds(2)

    private let log = Log.logger(.app)
    private var pending: Task<Void, Never>?

    func activate() {
        let start = ContinuousClock.now
        let wasActive = NSApp.isActive
        // Also when already active: it cancels a hand-over still pending from the last dismissal.
        NSApp.activate()
        pending?.cancel()
        guard !wasActive else { return }

        pending = Task { [log] in
            let deadline = start + Self.fallbackDelay
            while !NSApp.isActive, ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.pollInterval)
            }
            guard !Task.isCancelled else { return }
            let elapsed = Self.milliseconds(ContinuousClock.now - start)
            if NSApp.isActive {
                log.notice("Activation: activate() took \(elapsed, format: .fixed(precision: 1), privacy: .public) ms")
                return
            }
            log.notice("Activation: activate() not honoured after \(elapsed, format: .fixed(precision: 1), privacy: .public) ms; using activate(ignoringOtherApps:)")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
