import Foundation
import PIDesign

/// The fade-in of released runs, in a few even alpha steps over `EmberDesign.Stream.fadeDuration`
/// (0.35 → 0.7 → 1). Pure: the view applies the alphas as TextKit 2 rendering attributes, which
/// never touch layout.
nonisolated enum StreamFade {
    /// The alpha of a run released `elapsed` seconds ago, or `nil` once it is fully opaque.
    static func alpha(
        elapsed: TimeInterval,
        duration: TimeInterval = EmberDesign.Stream.fadeDuration,
        levels: [CGFloat] = StreamLocalTokens.fadeLevels
    ) -> CGFloat? {
        guard duration > 0, !levels.isEmpty else { return nil }
        let step = duration / Double(levels.count)
        // A hair of tolerance so a step lands on the frame that reaches it, not the one after.
        let index = Int(((max(elapsed, 0) + step * 1e-6) / step).rounded(.down))
        return index < levels.count ? levels[index] : nil
    }
}

/// The runs that are still fading in.
nonisolated struct StreamFadeTracker: Sendable {
    struct Run: Equatable, Sendable {
        let range: NSRange
        let start: TimeInterval
        var alpha: CGFloat
    }

    private(set) var runs: [Run] = []

    var isEmpty: Bool { runs.isEmpty }

    /// A run released at `time`; it starts at the first fade level.
    mutating func add(_ range: NSRange, at time: TimeInterval) {
        guard range.length > 0, let alpha = StreamFade.alpha(elapsed: 0) else { return }
        runs.append(Run(range: range, start: time, alpha: alpha))
    }

    /// Moves every run to its level at `time`.
    ///
    /// - Returns: Whether any visible alpha changed, and the ranges that finished (fully opaque).
    mutating func advance(to time: TimeInterval) -> (changed: Bool, finished: [NSRange]) {
        var changed = false
        var finished: [NSRange] = []
        var remaining: [Run] = []
        for var run in runs {
            guard let alpha = StreamFade.alpha(elapsed: time - run.start) else {
                finished.append(run.range)
                changed = true
                continue
            }
            if alpha != run.alpha {
                run.alpha = alpha
                changed = true
            }
            remaining.append(run)
        }
        runs = remaining
        return (changed, finished)
    }

    /// Every run, finished at once.
    mutating func removeAll() -> [NSRange] {
        defer { runs = [] }
        return runs.map(\.range)
    }
}
