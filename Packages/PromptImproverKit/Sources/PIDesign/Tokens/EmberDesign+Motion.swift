import QuartzCore
import SwiftUI

public nonisolated extension EmberDesign {
    /// The motion budget: the durations, curves and springs of every kit and panel animation.
    /// Never animated: keystrokes, hover, menu highlight, scrolling. Every helper that takes
    /// `reduceMotion` drops movement and scale under Reduce Motion and keeps opacity only.
    enum Motion {
        // MARK: Panel appear and hide (Core Animation, after the panel is key)

        public static let panelAppearDuration: TimeInterval = 0.16
        /// Ease-out with no overshoot.
        public static let panelAppearControlPoints: (Float, Float, Float, Float) = (0.2, 0.9, 0.3, 1.0)
        /// The panel scales up from this to 1 as it appears.
        public static let panelAppearScale: CGFloat = 0.97
        /// The panel rises this far (points) into place.
        public static let panelAppearRise: CGFloat = 4
        public static let panelHideDuration: TimeInterval = 0.11

        public static var panelAppearTimingFunction: CAMediaTimingFunction {
            let points = panelAppearControlPoints
            return CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
        }

        public static var panelHideTimingFunction: CAMediaTimingFunction {
            CAMediaTimingFunction(name: .easeIn)
        }

        // MARK: Submit (compose to running)

        /// The panel's height change on submit.
        public static let submitHeightSpringResponse: Double = 0.32
        public static let submitHeightSpringDamping: Double = 0.9
        public static let contentCrossfadeDuration: TimeInterval = 0.16

        /// Content crossfades (opacity only, so the same under Reduce Motion).
        public static var contentCrossfade: Animation { .easeInOut(duration: contentCrossfadeDuration) }

        // MARK: Caret

        /// One full breath: 1 → 0.3 → 1.
        public static let caretBreathePeriod: TimeInterval = 1.1
        public static let caretBreatheMaxOpacity: Float = 1
        public static let caretBreatheMinOpacity: Float = 0.3
        /// The caret fades out on completion.
        public static let caretFadeDuration: TimeInterval = 0.18

        // MARK: Target chip

        public static let targetChipCrossfadeDuration: TimeInterval = 0.12
        public static var targetChipCrossfade: Animation { .easeInOut(duration: targetChipCrossfadeDuration) }

        // MARK: Floating cards (menus, selects)

        public static let menuInDuration: TimeInterval = 0.14
        public static let menuOutDuration: TimeInterval = 0.09
        /// Menus and dialogs scale up from this as they appear.
        public static let menuScale: CGFloat = 0.96
        public static var menuIn: Animation { .easeOut(duration: menuInDuration) }
        public static var menuOut: Animation { .easeIn(duration: menuOutDuration) }

        /// Scale from the anchor plus a fade; the fade only under Reduce Motion.
        public static func menuTransition(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: menuScale, anchor: anchor))
        }

        // MARK: Dialogs

        /// The scrim's fade, and the whole dialog's under Reduce Motion.
        public static let dialogScrimDuration: TimeInterval = 0.12
        public static let dialogSpringResponse: Double = 0.26
        public static let dialogSpringDamping: Double = 0.9

        /// A dialog and its scrim appearing or leaving.
        public static func dialog(reduceMotion: Bool) -> Animation {
            reduceMotion
                ? .easeOut(duration: dialogScrimDuration)
                : .spring(response: dialogSpringResponse, dampingFraction: dialogSpringDamping)
        }

        /// The dialog card's own transition: a scale plus a fade, the fade only under Reduce
        /// Motion.
        public static func dialogTransition(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: menuScale))
        }

        // MARK: Toasts

        public static let toastInDuration: TimeInterval = 0.18
        public static let toastOutDuration: TimeInterval = 0.14
        /// Toasts rise this far as they appear.
        public static let toastRise: CGFloat = 8
        /// How long a toast, and its undo window, stays.
        public static let toastLifetime: TimeInterval = 5
        public static var toastIn: Animation { .easeOut(duration: toastInDuration) }
        public static var toastOut: Animation { .easeIn(duration: toastOutDuration) }

        /// A rise plus a fade; the fade only under Reduce Motion.
        public static func toastTransition(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .opacity.combined(with: .offset(y: toastRise))
        }

        // MARK: Deliver ("Copy and close" to the "Copied" pill)

        /// The panel window shrinks into the pill on this spring, which starts from rest and
        /// overshoots by about 1.5 %.
        public static let deliverSpringResponse: Double = 0.5
        public static let deliverSpringDamping: Double = 0.8
        /// When the spring has settled; the hold starts after it.
        public static let deliverSettleDuration: TimeInterval = 0.68
        /// The pill stays this long before the normal hide.
        public static let deliverHoldDuration: TimeInterval = 0.65
        /// Under Reduce Motion the panel fades out, takes the pill's frame and fades in, each
        /// fade this long.
        public static let deliverReducedFadeDuration: TimeInterval = 0.1

        // MARK: Controls

        /// A state swap inside a control ("Clear" to "Cleared", a key badge), and every control
        /// change under Reduce Motion: a short crossfade.
        public static let stateCrossfadeDuration: TimeInterval = 0.12
        public static var stateCrossfade: Animation { .easeInOut(duration: stateCrossfadeDuration) }

        /// The switch knob's slide, damped so that nothing visibly overshoots: 0.9 leaves 0.15 %
        /// of the travel, under a tenth of a point.
        public static let switchSpringResponse: Double = 0.24
        public static let switchSpringDamping: Double = 0.9
        /// The knob stretching under the pointer and back.
        public static let switchPressDuration: TimeInterval = 0.1

        /// The knob's slide and the track's tint, together; a crossfade under Reduce Motion (the
        /// knob fades across instead of travelling).
        public static func switchToggle(reduceMotion: Bool) -> Animation {
            reduceMotion ? stateCrossfade : .spring(response: switchSpringResponse, dampingFraction: switchSpringDamping)
        }

        /// The knob's stretch; none under Reduce Motion.
        public static func switchPress(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: switchPressDuration)
        }

        /// The selected chip's fill slides to the new choice, carrying its label colour with it.
        public static let selectionSpringResponse: Double = 0.28
        public static let selectionSpringDamping: Double = 0.9

        /// Chip selection: a slide, or a crossfade under Reduce Motion.
        public static func selection(reduceMotion: Bool) -> Animation {
            reduceMotion ? stateCrossfade : .spring(response: selectionSpringResponse, dampingFraction: selectionSpringDamping)
        }
    }
}
