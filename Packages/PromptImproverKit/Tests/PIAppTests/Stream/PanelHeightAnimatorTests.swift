import AppKit
@testable import PIApp
import PIDesign
import Testing

/// The pure height curves: follow, spring and ease.
struct PanelHeightMathTests {
    private let frame = 1.0 / 120.0
    private let response = EmberDesign.Motion.submitHeightSpringResponse
    private let damping = EmberDesign.Motion.submitHeightSpringDamping

    // MARK: Follow

    @Test func followIsMonotonicAndConverges() {
        var value = 100.0
        var previous = value
        var reachedAt: Double?
        for step in 1...240 {
            value = PanelHeightMath.followStep(value: value, target: 400, dt: frame, timeConstant: EmberDesign.Stream.followTimeConstant)
            #expect(value >= previous)
            #expect(value <= 400)
            previous = value
            if reachedAt == nil, 400 - value < PanelHeightMath.followSnapDistance {
                reachedAt = Double(step) * frame
            }
        }
        // 300 pt with τ = 80 ms: within half a point after τ·ln(600) ≈ 0.51 s.
        #expect(reachedAt.map { $0 < 0.55 } == true)
    }

    @Test func followIsIndependentOfTheFrameRate() {
        var at60 = 0.0
        var at120 = 0.0
        for _ in 0..<30 {
            at60 = PanelHeightMath.followStep(value: at60, target: 100, dt: 1.0 / 60, timeConstant: 0.08)
        }
        for _ in 0..<60 {
            at120 = PanelHeightMath.followStep(value: at120, target: 100, dt: 1.0 / 120, timeConstant: 0.08)
        }
        #expect(abs(at60 - at120) < 1e-9)
    }

    // MARK: Spring

    @Test func springConvergesWithoutMeaningfulOvershoot() {
        var state = PanelHeightMath.SpringState(position: 96, velocity: 0)
        let target = 500.0
        var peak = state.position
        var settledAt: Double?
        for step in 1...240 {
            state = PanelHeightMath.springStep(state, target: target, dt: frame, response: response, damping: damping)
            peak = max(peak, state.position)
            if settledAt == nil, PanelHeightMath.isSpringSettled(state, target: target) {
                settledAt = Double(step) * frame
            }
        }
        #expect(peak <= target + (target - 96) * 0.01)
        #expect(abs(state.position - target) < 0.01)
        // Visually done (98 %) by about 280 ms; at rest within the tolerance a little later.
        var probe = PanelHeightMath.SpringState(position: 96, velocity: 0)
        probe = PanelHeightMath.springStep(probe, target: target, dt: 0.28, response: response, damping: damping)
        #expect((probe.position - 96) / (target - 96) > 0.98)
        #expect(settledAt.map { $0 < 0.5 } == true)
    }

    @Test func springRetargetKeepsPositionAndVelocity() {
        var state = PanelHeightMath.SpringState(position: 100, velocity: 0)
        for _ in 0..<12 {
            state = PanelHeightMath.springStep(state, target: 500, dt: frame, response: response, damping: damping)
        }
        let before = state
        // A new target: the next frame moves on from the same place at the same speed.
        let after = PanelHeightMath.springStep(before, target: 300, dt: frame, response: response, damping: damping)
        #expect(abs(after.position - before.position) <= abs(before.velocity) * frame + 1)
        #expect(after.position > before.position, "momentum carries it on for a frame")
        // And it then settles on the new target.
        var settle = after
        for _ in 0..<240 {
            settle = PanelHeightMath.springStep(settle, target: 300, dt: frame, response: response, damping: damping)
        }
        #expect(abs(settle.position - 300) < 0.01)
    }

    @Test func springStepsComposeExactly() {
        let start = PanelHeightMath.SpringState(position: 50, velocity: 400)
        let once = PanelHeightMath.springStep(start, target: 200, dt: 2 * frame, response: response, damping: damping)
        let half = PanelHeightMath.springStep(start, target: 200, dt: frame, response: response, damping: damping)
        let twice = PanelHeightMath.springStep(half, target: 200, dt: frame, response: response, damping: damping)
        #expect(abs(once.position - twice.position) < 1e-9)
        #expect(abs(once.velocity - twice.velocity) < 1e-6)
    }

    @Test func criticalAndOverdampedSpringsAlsoConverge() {
        for ratio in [1.0, 1.4] {
            var state = PanelHeightMath.SpringState(position: 0, velocity: 0)
            var peak = 0.0
            for _ in 0..<240 {
                state = PanelHeightMath.springStep(state, target: 100, dt: frame, response: response, damping: ratio)
                peak = max(peak, state.position)
            }
            #expect(abs(state.position - 100) < 0.05)
            #expect(peak <= 100.0001)
        }
    }

    // MARK: Ease

    @Test func easeOutStartsFastAndLandsGently() {
        #expect(PanelHeightMath.easeOut(0) == 0)
        #expect(PanelHeightMath.easeOut(1) == 1)
        #expect(PanelHeightMath.easeOut(-1) == 0)
        #expect(PanelHeightMath.easeOut(2) == 1)
        #expect(PanelHeightMath.easeOut(0.5) > 0.5)
        var previous = 0.0
        for step in 1...100 {
            let value = PanelHeightMath.easeOut(Double(step) / 100)
            #expect(value >= previous)
            previous = value
        }
    }
}

/// The animator's rules, driven by real frames where it matters.
@Suite(.serialized)
struct PanelHeightAnimatorTests {
    /// Pumps the main run loop until `condition` holds or `timeout` passes.
    private func pump(timeout: TimeInterval = 2, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }

    @Test func instantAppliesAtOnceAndSettles() {
        var applied: [CGFloat] = []
        var settles = 0
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.onSettle = { settles += 1 }
        animator.setHeight(96, transition: .instant)
        #expect(applied == [96])
        #expect(animator.currentHeight == 96)
        #expect(!animator.isAnimating)
        #expect(settles == 1)
        animator.setHeight(96, transition: .instant)
        #expect(applied == [96])
    }

    @Test func reduceMotionMakesEveryTransitionInstant() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = true
        animator.setHeight(100, transition: .instant)
        animator.setHeight(300, transition: .spring)
        #expect(animator.currentHeight == 300)
        animator.setHeight(200, transition: .ease(duration: 0.18))
        #expect(animator.currentHeight == 200)
        animator.setHeight(260, transition: .follow)
        #expect(animator.currentHeight == 260)
        // A follow still never shrinks.
        animator.setHeight(250, transition: .follow)
        #expect(animator.currentHeight == 260)
        #expect(!animator.isAnimating)
        #expect(applied == [100, 300, 200, 260])
    }

    @Test func followIgnoresASmallerTarget() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.setHeight(300, transition: .instant)
        animator.setHeight(280, transition: .follow)
        #expect(!animator.isAnimating)
        #expect(applied == [300])
    }

    @Test func springRunsOnFramesAndLandsExactly() {
        var applied: [CGFloat] = []
        var settles = 0
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.onSettle = { settles += 1 }
        animator.setHeight(96, transition: .instant)
        settles = 0
        animator.setHeight(400, transition: .spring)
        #expect(animator.isAnimating)
        #expect(animator.targetHeight == 400)
        pump { !animator.isAnimating }
        #expect(!animator.isAnimating)
        #expect(animator.currentHeight == 400)
        #expect(applied.last == 400)
        #expect(applied.count > 5, "the spring should take several frames")
        #expect((applied.max() ?? 0) <= 400 + (400 - 96) * 0.01)
        #expect(settles == 1)
    }

    @Test func aFollowDuringASpringMovesTheSpringsTarget() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.setHeight(96, transition: .instant)
        animator.setHeight(300, transition: .spring)
        animator.setHeight(360, transition: .follow)
        #expect(animator.targetHeight == 360)
        animator.setHeight(340, transition: .follow)
        #expect(animator.targetHeight == 360)
        pump { !animator.isAnimating }
        #expect(animator.currentHeight == 360)
    }

    @Test func followGrowsInWholePointsMonotonically() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.setHeight(200, transition: .instant)
        animator.setHeight(260, transition: .follow)
        pump(timeout: 0.05) { false }
        animator.setHeight(300, transition: .follow)
        pump { !animator.isAnimating }
        #expect(animator.currentHeight == 300)
        #expect(applied.allSatisfy { $0 == $0.rounded() })
        #expect(zip(applied, applied.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func easeLandsOnTheTargetAndCanBeRetargeted() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.setHeight(100, transition: .instant)
        animator.setHeight(250, transition: .ease(duration: 0.18))
        pump(timeout: 0.06) { false }
        let midway = animator.currentHeight
        #expect(midway > 100 && midway < 250)
        animator.setHeight(150, transition: .ease(duration: 0.18))
        pump { !animator.isAnimating }
        #expect(animator.currentHeight == 150)
        // No jump at the retarget: the value after it starts from where it was.
        if let index = applied.firstIndex(of: midway), index + 1 < applied.count {
            #expect(abs(applied[index + 1] - midway) < 40)
        }
    }

    @Test func instantCancelsARunningAnimation() {
        var applied: [CGFloat] = []
        let animator = PanelHeightAnimator { applied.append($0) }
        animator.reduceMotionOverride = false
        animator.setHeight(100, transition: .instant)
        animator.setHeight(400, transition: .spring)
        animator.setHeight(180, transition: .instant)
        #expect(!animator.isAnimating)
        #expect(animator.currentHeight == 180)
        pump(timeout: 0.1) { false }
        #expect(applied.last == 180)
    }
}
