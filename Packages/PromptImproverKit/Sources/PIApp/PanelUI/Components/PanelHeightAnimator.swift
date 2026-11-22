import AppKit
import PIDesign
import QuartzCore

/// Drives the panel's height. Only one height animation ever runs; a new target retargets it.
///
/// Frames come from the display link of the screen the panel is on (`window`'s screen, else the
/// main screen): a screen's link keeps running whether or not the panel is key or fully visible,
/// unlike a view's. The curves are `PanelHeightMath`, testable on their own.
///
/// - `.instant` applies at once and cancels any animation.
/// - `.ease(duration:)` is a cubic ease-out from the current height.
/// - `.spring` is the submit spring (`EmberDesign.Motion.submitHeightSpringResponse` 0.32 s,
///   damping 0.9, visually done in about 280 ms); retargeting it mid-flight keeps position and
///   velocity, so nothing jumps.
/// - `.follow` tracks a moving target exponentially (`EmberDesign.Stream.followTimeConstant`) in
///   whole points and only ever grows: a smaller target is ignored. While a spring runs, a follow
///   target moves the spring's target instead, so the spring finishes at the latest height.
///
/// Under Reduce Motion every transition applies at once (a follow still never shrinks).
final class PanelHeightAnimator {
    /// How a new height is reached.
    enum Transition: Equatable {
        case instant
        /// An eased change, for a paste that adds several lines or the origin row opening.
        case ease(duration: TimeInterval)
        /// A change of screen, such as submit and completion.
        case spring
        /// Follows a moving target smoothly while text streams; only ever grows.
        case follow
    }

    private let apply: (CGFloat) -> Void
    /// The height last applied (what the panel shows now).
    private(set) var currentHeight: CGFloat = 0
    /// True while frames are pending.
    private(set) var isAnimating = false

    /// The height the panel is heading to: equal to `currentHeight` at rest.
    private(set) var targetHeight: CGFloat = 0

    /// Called when the height comes to rest after a change (the end of an animation, or an
    /// instant change), e.g. to `invalidateShadow()` once.
    var onSettle: (() -> Void)?

    /// The window whose screen paces the frames and whose backing scale the heights are rounded
    /// to. When `nil`, the main screen.
    weak var window: NSWindow?

    /// Overrides the system Reduce Motion setting (for tests).
    var reduceMotionOverride: Bool?

    private enum Motion {
        case spring(PanelHeightMath.SpringState)
        case ease(from: CGFloat, start: CFTimeInterval?, duration: TimeInterval)
        case follow(value: Double)
    }

    private var motion: Motion?
    /// The unrounded value of the running animation, and its velocity (points per second), so a
    /// new spring starts from exactly where and how fast the previous motion was going.
    private var presentation: Double = 0
    private var velocity: Double = 0
    private var lastFrameTime: CFTimeInterval?
    private lazy var ticker = FrameTicker { [weak self] time in
        self?.step(at: time)
    }

    /// - Parameter apply: Sets the panel's height, keeping its top edge where it is.
    init(apply: @escaping (CGFloat) -> Void) {
        self.apply = apply
    }

    private var reducesMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Moves the panel toward `height` with `transition` (see the type's notes for each).
    func setHeight(_ height: CGFloat, transition: Transition) {
        switch transition {
        case .instant:
            jump(to: height)

        case .follow:
            if case .spring = motion {
                // Paused while the spring runs: the spring lands on the latest height instead.
                if height > targetHeight {
                    targetHeight = height
                }
                return
            }
            let floor = isAnimating ? max(currentHeight, targetHeight) : currentHeight
            guard height > floor else { return }
            if reducesMotion {
                jump(to: height)
                return
            }
            if case .follow = motion {
                targetHeight = height
                return
            }
            // An ease in flight hands over to the follow where it stands.
            targetHeight = max(height, isAnimating ? targetHeight : height)
            begin(.follow(value: presentation))

        case .ease(let duration):
            guard !reducesMotion, duration > 0 else {
                jump(to: height)
                return
            }
            guard height != currentHeight || isAnimating else { return }
            targetHeight = height
            begin(.ease(from: CGFloat(presentation), start: nil, duration: duration))

        case .spring:
            guard !reducesMotion else {
                jump(to: height)
                return
            }
            targetHeight = height
            if case .spring = motion {
                return
            }
            guard height != currentHeight || isAnimating else { return }
            begin(.spring(PanelHeightMath.SpringState(position: presentation, velocity: velocity)))
        }
    }

    /// Stops any animation where it stands.
    func cancel() {
        guard isAnimating else { return }
        ticker.stop()
        motion = nil
        isAnimating = false
        lastFrameTime = nil
        velocity = 0
        targetHeight = currentHeight
    }

    // MARK: Driving

    private func jump(to height: CGFloat) {
        let wasAnimating = isAnimating
        cancel()
        targetHeight = height
        presentation = Double(height)
        velocity = 0
        let changed = height != currentHeight
        if changed {
            currentHeight = height
            apply(height)
        }
        if changed || wasAnimating {
            onSettle?()
        }
    }

    private func begin(_ newMotion: Motion) {
        motion = newMotion
        guard !isAnimating else { return }
        isAnimating = true
        lastFrameTime = nil
        ticker.start(.screen(window?.screen ?? NSScreen.main ?? NSScreen.screens.first))
    }

    private func step(at time: CFTimeInterval) {
        guard let motion else {
            ticker.stop()
            return
        }
        let dt = min(
            max(time - (lastFrameTime ?? time - StreamLocalTokens.nominalFrameInterval), 0),
            StreamLocalTokens.maximumFrameStep
        )
        lastFrameTime = time
        let target = Double(targetHeight)
        let previous = presentation

        switch motion {
        case .spring(let state):
            let next = PanelHeightMath.springStep(
                state,
                target: target,
                dt: dt,
                response: EmberDesign.Motion.submitHeightSpringResponse,
                damping: EmberDesign.Motion.submitHeightSpringDamping
            )
            if PanelHeightMath.isSpringSettled(next, target: target) {
                finish()
                return
            }
            self.motion = .spring(next)
            presentation = next.position
            velocity = next.velocity
            show(PanelHeightMath.roundedToPixel(next.position, scale: backingScale))

        case .ease(let from, let start, let duration):
            let origin = start ?? time - dt
            let progress = (time - origin) / duration
            if progress >= 1 {
                finish()
                return
            }
            self.motion = .ease(from: from, start: origin, duration: duration)
            let value = Double(from) + (target - Double(from)) * PanelHeightMath.easeOut(progress)
            presentation = value
            velocity = dt > 0 ? (value - previous) / dt : 0
            show(PanelHeightMath.roundedToPixel(value, scale: backingScale))

        case .follow(let value):
            let next = PanelHeightMath.followStep(
                value: value,
                target: target,
                dt: dt,
                timeConstant: EmberDesign.Stream.followTimeConstant
            )
            if abs(target - next) < PanelHeightMath.followSnapDistance {
                finish()
                return
            }
            self.motion = .follow(value: next)
            presentation = next
            velocity = dt > 0 ? (next - previous) / dt : 0
            // Whole points, never below what is already shown (the follow only grows).
            show(max(next.rounded(), Double(currentHeight)))
        }
    }

    private func show(_ value: Double) {
        let height = CGFloat(value)
        guard height != currentHeight else { return }
        currentHeight = height
        apply(height)
    }

    private func finish() {
        ticker.stop()
        motion = nil
        isAnimating = false
        lastFrameTime = nil
        velocity = 0
        presentation = Double(targetHeight)
        show(presentation)
        onSettle?()
    }

    private var backingScale: Double {
        Double(window?.backingScaleFactor ?? window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
    }
}
