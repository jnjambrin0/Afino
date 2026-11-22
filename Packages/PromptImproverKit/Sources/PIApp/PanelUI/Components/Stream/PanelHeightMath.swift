import Foundation

/// The curves behind `PanelHeightAnimator` and the well's pinned scrolling in `StreamTextView`:
/// pure, so every curve is testable without a display link.
nonisolated enum PanelHeightMath {
    /// A spring's position and velocity (points, points per second).
    struct SpringState: Equatable, Sendable {
        var position: Double
        var velocity: Double
    }

    /// Advances a damped spring toward `target` by `dt` seconds, exactly (the closed-form
    /// solution, so any frame interval is stable). `response` is the undamped period in seconds;
    /// `damping` is the damping ratio (1 = critical). Retargeting keeps position and velocity, so
    /// a new target never makes the value jump.
    static func springStep(
        _ state: SpringState,
        target: Double,
        dt: Double,
        response: Double,
        damping: Double
    ) -> SpringState {
        guard dt > 0, response > 0 else { return state }
        let omega = 2 * Double.pi / response
        let zeta = max(damping, 0)
        let x = state.position - target
        let v = state.velocity

        if zeta < 1 {
            let decay = zeta * omega
            let dampedOmega = omega * (1 - zeta * zeta).squareRoot()
            let envelope = exp(-decay * dt)
            let c1 = x
            let c2 = (v + decay * x) / dampedOmega
            let cosine = cos(dampedOmega * dt)
            let sine = sin(dampedOmega * dt)
            let position = envelope * (c1 * cosine + c2 * sine)
            let velocity = envelope * ((c2 * dampedOmega - decay * c1) * cosine - (c1 * dampedOmega + decay * c2) * sine)
            return SpringState(position: target + position, velocity: velocity)
        }
        if zeta == 1 {
            let envelope = exp(-omega * dt)
            let c2 = v + omega * x
            let position = envelope * (x + c2 * dt)
            let velocity = envelope * (c2 - omega * (x + c2 * dt))
            return SpringState(position: target + position, velocity: velocity)
        }
        let root = (zeta * zeta - 1).squareRoot()
        let r1 = -omega * (zeta - root)
        let r2 = -omega * (zeta + root)
        let a = (v - r2 * x) / (r1 - r2)
        let b = x - a
        let e1 = exp(r1 * dt)
        let e2 = exp(r2 * dt)
        return SpringState(position: target + a * e1 + b * e2, velocity: a * r1 * e1 + b * r2 * e2)
    }

    /// Whether a spring is close enough to rest at `target` to snap there.
    static func isSpringSettled(
        _ state: SpringState,
        target: Double,
        positionTolerance: Double = settlePositionTolerance,
        velocityTolerance: Double = settleVelocityTolerance
    ) -> Bool {
        abs(state.position - target) < positionTolerance && abs(state.velocity) < velocityTolerance
    }

    /// A spring within a quarter of a point of its target…
    static let settlePositionTolerance = 0.25
    /// …and slower than 20 pt/s (a sixth of a point per frame at 120 Hz) is at rest: nothing
    /// visible is left of its motion.
    static let settleVelocityTolerance = 20.0

    /// One step of an exponential follow: closes `1 − e^(−dt/τ)` of the gap to `target`, so the
    /// value never overshoots and moves monotonically toward a fixed target.
    static func followStep(value: Double, target: Double, dt: Double, timeConstant: Double) -> Double {
        guard dt > 0 else { return value }
        guard timeConstant > 0 else { return target }
        return value + (target - value) * (1 - exp(-dt / timeConstant))
    }

    /// A follow is done when it is within half a point of its target.
    static let followSnapDistance = 0.5

    /// Ease-out (cubic): fast start, gentle landing, no overshoot. `progress` is clamped to 0…1.
    static func easeOut(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        let remaining = 1 - p
        return 1 - remaining * remaining * remaining
    }

    /// `value` rounded to the nearest device pixel; `scale` is the backing scale factor (pixels
    /// per point).
    static func roundedToPixel(_ value: Double, scale: Double) -> Double {
        guard scale > 0 else { return value.rounded() }
        return (value * scale).rounded() / scale
    }
}
