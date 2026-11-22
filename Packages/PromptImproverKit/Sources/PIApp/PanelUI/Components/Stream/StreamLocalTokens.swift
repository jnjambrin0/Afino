import Foundation
import PIDesign

/// Timing and geometry that only the result well and the panel's height animation use, kept
/// together in one place. They stay out of `EmberDesign` because no other surface shares them.
nonisolated enum StreamLocalTokens {
    /// No streamed character waits longer than this before it is shown, and `finishStreaming()`
    /// shows whatever is pending within it.
    static let maximumLag: TimeInterval = 0.25

    /// The alpha steps a released run shows before it is fully opaque, evenly spread over
    /// `EmberDesign.Stream.fadeDuration` (0.35 → 0.7 → 1).
    static let fadeLevels: [CGFloat] = [0.35, 0.7]

    /// The trailing caret goes back to breathing after this long without a release.
    static let caretIdleDelay: TimeInterval = 0.4

    /// The caret sits this far after the last character.
    static let caretGap: CGFloat = 1

    /// The text's opacity while a refinement is in flight (the previous version stays readable).
    static let dimmedTextOpacity: CGFloat = 0.45

    /// The well counts as having stopped growing once its height has been still for this long
    /// with text below its bottom edge; only then does pinned scrolling start to follow.
    static let growthSettleDelay: TimeInterval = 0.15

    /// The "Jump to latest" capsule sits this far above the well's bottom edge.
    static var jumpPillBottomInset: CGFloat { EmberDesign.Spacing.s }

    /// The frame interval assumed for the first frame of an animation, and the period of the
    /// fallback timer when no display link is available (a 60 Hz frame).
    static let nominalFrameInterval: TimeInterval = 1.0 / 60.0

    /// A frame that arrives late (a stall) advances animations by at most this much, so nothing
    /// lurches forward.
    static let maximumFrameStep: TimeInterval = 1.0 / 20.0

    /// How many drain ticks fit in `maximumLag` (7 at 33 ms, i.e. 231 ms).
    static var maximumLagTicks: Int {
        max(1, Int((maximumLag / EmberDesign.Stream.drainInterval).rounded(.down)))
    }
}
