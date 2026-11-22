import AppKit
import QuartzCore

/// Calls back once per display frame with the time that frame reaches the screen
/// (`CACurrentMediaTime` clock), until stopped.
///
/// - `.view`: the view's display link. It follows the view's screen and pauses while the view's
///   window is not visible, which suits content inside the window.
/// - `.screen`: a screen's display link. It runs whether or not a window on it is visible or key,
///   which suits driving the window itself (its frame).
///
/// Falls back to a run-loop timer when there is nothing to take a display link from (no window,
/// a window that is not ordered in, or no screen at all), so the work still advances.
@MainActor
final class FrameTicker {
    enum Source {
        case view(NSView)
        case screen(NSScreen?)
    }

    private let handler: (CFTimeInterval) -> Void
    private var link: CADisplayLink?
    private var timer: Timer?
    private var proxy: Proxy?

    init(handler: @escaping (CFTimeInterval) -> Void) {
        self.handler = handler
    }

    /// Whether a display link or the fallback timer is calling back.
    var isRunning: Bool { link != nil || timer != nil }

    /// Starts calling back; a running ticker restarts on the new source.
    func start(_ source: Source) {
        stop()
        let proxy = Proxy(owner: self)
        self.proxy = proxy
        switch source {
        case .view(let view) where view.window?.isVisible == true:
            link = view.displayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        case .screen(let screen?):
            link = screen.displayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        default:
            break
        }
        if let link {
            link.add(to: .main, forMode: .common)
            return
        }
        let interval = StreamLocalTokens.nominalFrameInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak proxy] timer in
            let isOwned = MainActor.assumeIsolated { () -> Bool in
                guard let owner = proxy?.owner else { return false }
                owner.tick(at: CACurrentMediaTime() + interval)
                return true
            }
            // An owner that went away without stopping must not leave the timer running.
            if !isOwned {
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops calling back; safe to call when already stopped.
    func stop() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
        proxy = nil
    }

    fileprivate func tick(at time: CFTimeInterval) {
        handler(time)
    }

    /// The display link's target: it retains its target, so the ticker hands it this weak proxy.
    private final class Proxy: NSObject {
        weak var owner: FrameTicker?

        init(owner: FrameTicker) {
            self.owner = owner
        }

        @objc func step(_ link: CADisplayLink) {
            // An owner that went away without stopping must not leave the link running.
            guard let owner else {
                link.invalidate()
                return
            }
            owner.tick(at: link.targetTimestamp)
        }
    }
}
