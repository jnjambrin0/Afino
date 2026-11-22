import AppKit
import QuartzCore
import Testing
@testable import PIDesign

struct AccentCaretTests {
    @Test
    func caretIsTwoPointsWideWithRoundedEnds() {
        let caret = EAccentCaretView()
        caret.lineHeight = 20
        #expect(caret.intrinsicContentSize == NSSize(width: 2, height: 20))
        #expect(caret.caretLayer.cornerRadius == 1)
        #expect(caret.isAccessibilityElement() == false)
        caret.setFrameSize(NSSize(width: 2, height: 20))
        #expect(caret.caretLayer.frame == CGRect(x: 0, y: 0, width: 2, height: 20))
    }

    @Test
    func breathesBetweenFullAndThirtyPercent() {
        let caret = EAccentCaretView()
        caret.reduceMotionOverride = false
        caret.breathe()
        #expect(caret.mode == .breathing)
        let animation = caret.caretLayer.animation(forKey: EAccentCaretView.breatheKey) as? CABasicAnimation
        #expect(animation?.fromValue as? Float == 1)
        #expect(animation?.toValue as? Float == 0.3)
        #expect(animation?.duration == 0.55, "one full breath is 1.1 s")
        #expect(animation?.autoreverses == true)
        #expect(animation?.repeatCount == .infinity)

        caret.breathe()
        #expect(caret.caretLayer.animationKeys() == [EAccentCaretView.breatheKey], "a running breath is not restarted")
    }

    @Test
    func staysStaticUnderReduceMotion() {
        let caret = EAccentCaretView()
        caret.reduceMotionOverride = true
        caret.breathe()
        #expect(caret.mode == .breathing)
        #expect(caret.caretLayer.animationKeys() == nil)
        #expect(caret.caretLayer.opacity == 1)
    }

    @Test
    func solidStopsTheBreath() {
        let caret = EAccentCaretView()
        caret.reduceMotionOverride = false
        caret.breathe()
        caret.solid()
        #expect(caret.mode == .solid)
        #expect(caret.caretLayer.animationKeys() == nil)
        #expect(caret.caretLayer.opacity == 1)
    }

    @Test
    func fadesOutOverOneHundredEightyMilliseconds() {
        let caret = EAccentCaretView()
        caret.reduceMotionOverride = false
        caret.breathe()
        caret.fadeOut()
        #expect(caret.mode == .hidden)
        #expect(caret.caretLayer.opacity == 0)
        #expect(caret.caretLayer.animation(forKey: EAccentCaretView.breatheKey) == nil)
        let fade = caret.caretLayer.animation(forKey: EAccentCaretView.fadeKey) as? CABasicAnimation
        #expect(fade?.duration == 0.18)
        #expect(fade?.toValue as? Float == 0)
    }

    @Test
    func applyIsIdempotentPerMode() {
        let caret = EAccentCaretView()
        caret.reduceMotionOverride = false
        caret.apply(.breathing)
        caret.apply(.breathing)
        #expect(caret.caretLayer.animationKeys() == [EAccentCaretView.breatheKey])
        caret.apply(.solid)
        #expect(caret.caretLayer.animationKeys() == nil)
        caret.apply(.hidden)
        #expect(caret.mode == .hidden)
    }

    @Test
    func colorIsTheAccentMarkOfTheAppearance() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        let lightColor = EAccentCaretView.resolvedColor(for: light)
        let darkColor = EAccentCaretView.resolvedColor(for: dark)
        #expect(Int((lightColor.redComponent * 255).rounded()) == 0x00)
        #expect(Int((lightColor.greenComponent * 255).rounded()) == 0x74)
        #expect(Int((darkColor.greenComponent * 255).rounded()) == 0xE6)
    }
}
