import AppKit
import PIDesign
import QuartzCore

/// The panel's own motion, done in Core Animation on the window and the glass container so the
/// panel is on screen (and focusable) before any animation starts:
///
/// - appear: opacity 0→1, scale 0.97→1 and a 4 pt rise in 160 ms, ease-out with no overshoot
///   (Reduce Motion: opacity only);
/// - hide: 110 ms fade, then `orderOut`;
/// - Copy & Close: the window shrinks into the "Copied" pill (`PanelShrinkAnimator`), or under
///   Reduce Motion fades out, takes the pill's frame and fades in (`crossfade`).
///
/// Height changes while the panel is up belong to `PanelHeightAnimator`.
@MainActor
enum PanelMotion {
    private static let appearAnimationKey = "panelAppear"

    /// Fades the panel in and, unless Reduce Motion is on, scales and lifts the glass into place.
    static func appear(_ panel: NSWindow, surface: NSView, reduceMotion: Bool) {
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.panelAppearDuration
            context.timingFunction = appearTiming
            panel.animator().alphaValue = 1
        }

        guard !reduceMotion, let layer = surface.layer else {
            return
        }

        let scale = EmberDesign.Motion.panelAppearScale
        let bounds = surface.bounds
        // Layer-backed AppKit views keep their anchor at the origin, so scale around the centre
        // by translating there and back; the panel also rises a few points into place (layer y
        // grows upward).
        var from = CATransform3DMakeTranslation(bounds.midX, bounds.midY - EmberDesign.Motion.panelAppearRise, 0)
        from = CATransform3DScale(from, scale, scale, 1)
        from = CATransform3DTranslate(from, -bounds.midX, -bounds.midY, 0)

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = from
        animation.toValue = CATransform3DIdentity
        animation.duration = EmberDesign.Motion.panelAppearDuration
        animation.timingFunction = appearTiming
        layer.add(animation, forKey: appearAnimationKey)
    }

    /// Ends an appear animation in flight (a panel hidden while it was still appearing).
    static func cancelAppear(surface: NSView) {
        surface.layer?.removeAnimation(forKey: appearAnimationKey)
    }

    /// Fades the panel out; `completion` runs once it is invisible.
    static func hide(_ panel: NSWindow, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.panelHideDuration
            context.timingFunction = EmberDesign.Motion.panelHideTimingFunction
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                completion()
            }
        }
    }

    /// Reduce Motion: fade out, take the pill's frame while invisible, fade in.
    static func crossfade(_ panel: NSWindow, to frame: CGRect, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.setFrame(frame, display: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    /// Sets the frame at once, cancelling an AppKit frame animation in flight (the shrink itself
    /// is `PanelShrinkAnimator`, cancelled separately).
    static func setFrameImmediately(_ panel: NSWindow, _ frame: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(frame, display: false)
        }
        panel.setFrame(frame, display: false)
    }

    private static var appearTiming: CAMediaTimingFunction {
        EmberDesign.Motion.panelAppearTimingFunction
    }
}

/// Shrinks the panel window into a confirmation pill with a soft spring: it starts from rest,
/// so it begins slowly, gathers speed and settles with a barely visible bounce. Each display
/// frame sets the window frame; the glass and the native shadow follow the window. The curve is
/// `PanelShrinkSpring`, testable on its own.
@MainActor
final class PanelShrinkAnimator: NSObject {
    private weak var panel: NSWindow?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval?
    private var from: CGRect = .zero
    private var to: CGRect = .zero

    /// Starts shrinking `panel` from its current frame into `target`, replacing a shrink in flight.
    func run(_ panel: NSWindow, to target: CGRect) {
        cancel()
        guard let view = panel.contentView else {
            panel.setFrame(target, display: true)
            return
        }
        self.panel = panel
        from = panel.frame
        to = target
        startTime = nil
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        startTime = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let panel else {
            cancel()
            return
        }
        if startTime == nil {
            startTime = link.timestamp
        }
        let elapsed = link.targetTimestamp - (startTime ?? link.timestamp)
        let progress = PanelShrinkSpring.progress(at: elapsed)
        if PanelShrinkSpring.isSettled(at: elapsed) {
            panel.setFrame(to, display: true)
            cancel()
            return
        }
        panel.setFrame(PanelShrinkSpring.frame(from: from, to: to, progress: progress), display: true)
    }
}

/// The shrink's curve: a spring released from rest (slow start, quicker middle) with a slight
/// overshoot (about 1.5 % of the travel) before it settles.
nonisolated enum PanelShrinkSpring {
    /// How far along the shrink is `elapsed` seconds in: 0 at the start, 1 at rest, a little
    /// over 1 while it overshoots.
    static func progress(at elapsed: TimeInterval) -> CGFloat {
        let t = max(elapsed, 0)
        let response = EmberDesign.Motion.deliverSpringResponse
        let damping = EmberDesign.Motion.deliverSpringDamping
        let omega = 2 * Double.pi / response
        let decay = damping * omega
        let dampedOmega = omega * (1 - damping * damping).squareRoot()
        let value = 1 - exp(-decay * t) * (cos(dampedOmega * t) + (decay / dampedOmega) * sin(dampedOmega * t))
        return CGFloat(value)
    }

    static func isSettled(at elapsed: TimeInterval) -> Bool {
        elapsed >= EmberDesign.Motion.deliverSettleDuration
    }

    /// Interpolates the size and the centre separately, so the pill stays centred while the
    /// spring overshoots.
    static func frame(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let width = from.width + (to.width - from.width) * progress
        let height = from.height + (to.height - from.height) * progress
        let midX = from.midX + (to.midX - from.midX) * progress
        let midY = from.midY + (to.midY - from.midY) * progress
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}
