import AppKit
import os
import PIFoundation
import QuartzCore

/// Calls back on the `frames`-th display frame of a screen, with the time that frame reaches
/// the display (`CACurrentMediaTime` clock), then stops.
///
/// The screen's display link, not a view's: a view's link pauses while its window is invisible,
/// which the prewarm paint (alpha 0) and the first frame of the fade-in both are. If no frame
/// arrives within `timeout`, it calls back with nil, so nothing is ever left waiting.
@MainActor
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var timeoutTask: Task<Void, Never>?
    private var remaining: Int
    private var action: ((CFTimeInterval?) -> Void)?

    init(screen: NSScreen?, frames: Int, timeout: Duration = .milliseconds(500), action: @escaping (CFTimeInterval?) -> Void) {
        remaining = max(frames, 1)
        self.action = action
        super.init()
        if let screen {
            let link = screen.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(at: nil)
        }
    }

    func cancel() {
        link?.invalidate()
        link = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        action = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        remaining -= 1
        guard remaining <= 0 else { return }
        finish(at: link.targetTimestamp)
    }

    private func finish(at time: CFTimeInterval?) {
        let action = action
        cancel()
        action?(time)
    }
}

/// Measures each show of the panel: an `OSSignposter` interval ("PanelShow", in Instruments'
/// Points of Interest under the panel category) and a log line from the shortcut's key press —
/// or the request, for the menu bar and a reopen — to the first display frame with the panel
/// ordered in. Targets: under 120 ms on the first show, under 50 ms afterwards.
@MainActor
final class PanelShowMetrics {
    private let log = Log.logger(.panel)
    private let signposter = OSSignposter(logger: Log.logger(.panel))
    private var probe: FrameProbe?
    private var interval: OSSignpostIntervalState?
    private var start: TimeInterval = 0
    private var showCount = 0

    /// At the start of a show.
    func begin() {
        cancel()
        start = ProcessInfo.processInfo.systemUptime
        interval = signposter.beginInterval("PanelShow", id: signposter.makeSignpostID())
    }

    /// Once the panel is ordered in and key: waits for the next display frame of `screen`.
    ///
    /// - Parameter pressedAt: When the shortcut's key went down, on the same clock as
    ///   `ProcessInfo.systemUptime` and the display link (`CACurrentMediaTime`).
    func panelOrderedIn(on screen: NSScreen?, pressedAt: TimeInterval?) {
        showCount += 1
        let isFirstShow = showCount == 1
        let origin = pressedAt ?? start
        let presentWork = (ProcessInfo.processInfo.systemUptime - start) * 1000
        probe = FrameProbe(screen: screen, frames: 1) { [weak self] frameTime in
            guard let self else { return }
            probe = nil
            endInterval()
            guard let frameTime else {
                log.error("""
                    Panel shown, but no display frame was seen within 500 ms (displays asleep or \
                    locked?); present() \(presentWork, format: .fixed(precision: 1), privacy: .public) ms
                    """)
                return
            }
            let latency = (frameTime - origin) * 1000
            log.notice("""
                Panel shown (\(isFirstShow ? "first" : "again", privacy: .public)): \
                \(pressedAt == nil ? "request" : "shortcut", privacy: .public) → first frame \
                \(latency, format: .fixed(precision: 1), privacy: .public) ms, \
                present() \(presentWork, format: .fixed(precision: 1), privacy: .public) ms
                """)
        }
    }

    /// The panel went away before its first frame.
    func cancel() {
        probe?.cancel()
        probe = nil
        endInterval()
    }

    private func endInterval() {
        if let interval { signposter.endInterval("PanelShow", interval) }
        interval = nil
    }
}
