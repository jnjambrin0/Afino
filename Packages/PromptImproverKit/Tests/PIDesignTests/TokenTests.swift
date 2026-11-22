import AppKit
import SwiftUI
import Testing
@testable import PIDesign

struct TokenTests {
    @Test
    func spacingScaleIsTheFourEightGrid() {
        typealias Spacing = EmberDesign.Spacing
        #expect([Spacing.xxs, Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl, Spacing.xxl] == [2, 4, 8, 12, 16, 20, 24])
    }

    @Test
    func radiiAreConcentric() {
        typealias Radius = EmberDesign.Radius
        #expect(Radius.window == 26)
        #expect([Radius.small, Radius.medium, Radius.large] == [6, 10, 16])
        #expect(Radius.keyCap == 4)
        #expect(Radius.monogram == 5)
        #expect(Radius.caret == 1)

        #expect(Radius.inner(outer: 26, inset: 10) == 16)
        #expect(Radius.inner(outer: 10, inset: 4) == 6)
        #expect(Radius.inner(outer: 6, inset: 10) == 0, "never negative")
        // A shape inset by the panel's content inset is concentric with the window.
        #expect(Radius.well == Radius.window - EmberDesign.Panel.contentInset)
        #expect(Radius.well == Radius.large)
        #expect(Radius.control == Radius.window - EmberDesign.Panel.contentInset - EmberDesign.Spacing.s)
        // A highlighted menu row is concentric with its card.
        #expect(Radius.menuRow == Radius.inner(outer: Radius.large, inset: EmberDesign.Card.menuPadding))
        #expect(Radius.menuRow == 11)
    }

    @Test
    func controlsInARowShareOneHeight() {
        typealias Control = EmberDesign.Control
        #expect(Control.fieldHeight == Control.height, "fields line up with buttons and selects")
        #expect(Control.chipHeight <= Control.minimumHitTarget)
    }

    @Test
    func switchIsACapsuleWithARoundKnob() {
        typealias Control = EmberDesign.Control
        let size = Control.switchSize
        let knob = size.height - Control.switchKnobInset * 2
        #expect(size.width > size.height, "a capsule track, wider than tall")
        #expect(knob > 0 && knob < size.height)
        // The knob travels further than it stretches, so a press never reaches the other end.
        let travel = size.width - Control.switchKnobInset * 2 - knob
        #expect(Control.switchKnobPressStretch < travel)
        #expect(size.height <= Control.minimumHitTarget && size.width <= Control.minimumHitTarget * 2)
    }

    @Test
    func floatingCardsBackTheirContentAndGoOpaqueForAccessibility() {
        typealias Glass = EmberDesign.Glass
        #expect(Glass.cardTint(for: .light) != Glass.cardTint(for: .dark))
        #expect(Glass.cardTintLight > Glass.tintLight && Glass.cardTintDark > Glass.tintDark, "calmer than the panel glass")
        #expect(Glass.cardFill(colorScheme: .dark) == Glass.cardTint(for: .dark))
        let opaque = Color(nsColor: .windowBackgroundColor)
        #expect(Glass.cardFill(colorScheme: .light, contrast: .increased) == opaque)
        #expect(Glass.cardFill(colorScheme: .dark, reduceTransparency: true) == opaque)
    }

    @Test
    func panelGeometry() {
        typealias Panel = EmberDesign.Panel
        #expect(Panel.width == 680)
        #expect(Panel.contentInset == 10)
        #expect(Panel.topOffsetFraction == 0.22)
        #expect(Panel.inputLineHeight == 20)
        #expect(Panel.inputMinHeight == 52)
        #expect(Panel.inputMaxLines == 10)
        #expect(Panel.headerHeight == 40)
        #expect(Panel.footerHeight == 44)
        #expect(Panel.wellHorizontalPadding == 16)
        #expect(Panel.wellVerticalPadding == 14)
        #expect(Panel.wellMinHeight == 91)
        #expect(Panel.noticeRowHeight == 36)
        #expect(Panel.maxHeightCap == 720)
        #expect(Panel.bottomMargin == 24)
        #expect(Panel.minUsableHeight == 420)
        #expect(Panel.composeHeight == 96, "one input line plus the footer")
    }

    @Test
    func inputGrowsOneLineAtATimeUpToTenLines() {
        typealias Panel = EmberDesign.Panel
        #expect(Panel.inputHeight(forLines: 0) == 52)
        #expect(Panel.inputHeight(forLines: 1) == 52)
        #expect(Panel.inputHeight(forLines: 2) == 72)
        #expect(Panel.inputHeight(forLines: 10) == 232)
        #expect(Panel.inputHeight(forLines: 40) == 232)
    }

    @Test
    func streamRevealReleasesAFifthWithAFloorOfTwo() {
        typealias Stream = EmberDesign.Stream
        #expect(Stream.drainInterval == 0.033)
        #expect(Stream.drainFraction == 0.2)
        #expect(Stream.minimumRelease == 2)
        #expect(Stream.fadeDuration == 0.1)
        #expect(Stream.followTimeConstant == 0.08)
        #expect(Stream.unpinDistance == 24)
        #expect(Stream.edgeFade == 12)
        #expect(Stream.wordBoundaryLookahead == 12)

        #expect(Stream.releaseCount(pending: 0) == 0)
        #expect(Stream.releaseCount(pending: 1) == 1, "never more than what is pending")
        #expect(Stream.releaseCount(pending: 5) == 2)
        #expect(Stream.releaseCount(pending: 11) == 3, "ceil(2.2)")
        #expect(Stream.releaseCount(pending: 100) == 20)
    }

    @Test
    func motionBudget() {
        typealias Motion = EmberDesign.Motion
        #expect(Motion.panelAppearDuration == 0.16)
        #expect(Motion.panelAppearControlPoints == (0.2, 0.9, 0.3, 1.0))
        #expect(Motion.panelAppearScale == 0.97)
        #expect(Motion.panelAppearRise == 4)
        #expect(Motion.panelHideDuration == 0.11)
        #expect(Motion.submitHeightSpringResponse == 0.32)
        #expect(Motion.submitHeightSpringDamping == 0.9)
        #expect(Motion.contentCrossfadeDuration == 0.16)
        #expect(Motion.caretBreathePeriod == 1.1)
        #expect(Motion.caretBreatheMaxOpacity == 1)
        #expect(Motion.caretBreatheMinOpacity == 0.3)
        #expect(Motion.caretFadeDuration == 0.18)
        #expect(Motion.targetChipCrossfadeDuration == 0.12)
        #expect(Motion.menuInDuration == 0.14)
        #expect(Motion.menuOutDuration == 0.09)
        #expect(Motion.toastInDuration == 0.18)
        #expect(Motion.toastOutDuration == 0.14)
        #expect(Motion.toastLifetime == 5)
        #expect(Motion.deliverSpringResponse == 0.5)
        #expect(Motion.deliverSpringDamping == 0.8)
        #expect(Motion.deliverHoldDuration == 0.65)
        #expect(Motion.stateCrossfadeDuration == 0.12)
        #expect(Motion.switchPressDuration <= 0.1, "press feedback is immediate")
        // The switch and the chip slide are damped so nothing visibly overshoots.
        #expect(Motion.switchSpringDamping >= 0.9)
        #expect(Motion.selectionSpringDamping >= 0.9)
    }

    @Test
    func reduceMotionDropsMovementButKeepsFades() {
        typealias Motion = EmberDesign.Motion
        #expect(Motion.switchToggle(reduceMotion: true) == Motion.stateCrossfade, "the knob fades across")
        #expect(Motion.switchPress(reduceMotion: true) == nil)
        #expect(Motion.switchPress(reduceMotion: false) != nil)
        #expect(Motion.selection(reduceMotion: true) == Motion.stateCrossfade)
        #expect(Motion.selection(reduceMotion: false) != Motion.stateCrossfade)
    }

    @Test
    func wellMaterialIsOpaqueUnderIncreaseContrastOrReduceTransparency() {
        typealias Materials = EmberDesign.Materials
        #expect(Materials.wellOpacity(colorScheme: .light) == 0.6)
        #expect(Materials.wellOpacity(colorScheme: .dark) == 0.42)
        #expect(Materials.wellOpacity(colorScheme: .light, contrast: .increased) == 1)
        #expect(Materials.wellOpacity(colorScheme: .dark, reduceTransparency: true) == 1)
        #expect(Materials.wellStrokeWidth(contrast: .increased) == 1)
        #expect(Materials.wellStrokeWidth(contrast: .standard) == 0)
    }

    @Test
    func glassTintPerAppearance() {
        typealias Glass = EmberDesign.Glass
        #expect(Glass.tintAlpha(isDark: false) == 0.55)
        #expect(Glass.tintAlpha(isDark: true) == 0.5)
    }

    @Test
    func controlsMeetTheHitTargetAndChipGeometry() {
        #expect(EmberDesign.Control.minimumHitTarget == 28)
        #expect(EmberDesign.Control.iconButtonSize >= EmberDesign.Control.minimumHitTarget)
        #expect(EmberDesign.Chip.targetHeight == 28)
        #expect(EmberDesign.Chip.monogramSize == 18)
        #expect(EmberDesign.Chip.leadingInset == 5)
        #expect(EmberDesign.Caret.width == 2)
        #expect(EmberDesign.Caret.cornerRadius == 1)
        #expect(EmberDesign.Confirmation.pillRadius == 24)
    }

    @Test
    func tokensAreReadableOffTheMainActor() async {
        let values = await Task.detached { Self.readTokens() }.value
        #expect(values == [8, 26, 680, 2])
    }

    nonisolated static func readTokens() -> [CGFloat] {
        [
            EmberDesign.Spacing.s,
            EmberDesign.Radius.window,
            EmberDesign.Panel.width,
            CGFloat(EmberDesign.Stream.releaseCount(pending: 3)),
        ]
    }
}
