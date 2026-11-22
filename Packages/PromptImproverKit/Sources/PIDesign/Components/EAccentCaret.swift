import AppKit
import QuartzCore
import SwiftUI

/// The accent caret, the app's signature: 2 pt wide, rounded ends, in
/// `Brand.accentMark`. It breathes while the model thinks, stays solid while
/// text streams, and fades out on completion. Under Reduce Motion it never
/// breathes (it stays solid); the fade is opacity only and is kept.
///
/// Layer-backed: Core Animation runs the breath, so it costs no main-thread
/// work. Position it with its frame (or use `EAccentCaret` in SwiftUI). A
/// text view that draws its own `CALayer` caret can reuse
/// `breatheAnimation()`, `fadeOutAnimation(from:)` and `resolvedColor(for:)`.
public final class EAccentCaretView: NSView {
    /// What the caret is doing.
    public enum Mode: Sendable {
        /// Fully opaque and still: text is streaming.
        case solid
        /// Pulsing: the model is thinking.
        case breathing
        /// Faded out: the run is over.
        case hidden
    }

    /// The current mode. Change it with `apply(_:)`, `breathe()`, `solid()` or `fadeOut(completion:)`.
    public private(set) var mode: Mode = .solid

    /// Overrides the system Reduce Motion setting (tests, previews).
    public var reduceMotionOverride: Bool?

    /// The caret's intrinsic height: one line of the text it follows.
    public var lineHeight: CGFloat = EmberDesign.Caret.defaultHeight {
        didSet { invalidateIntrinsicContentSize() }
    }

    static let breatheKey = "ember.caret.breathe"
    static let fadeKey = "ember.caret.fade"

    /// The bar itself. A sublayer, so AppKit never resets what Core Animation
    /// animates on it.
    let caretLayer = CALayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        caretLayer.cornerRadius = EmberDesign.Caret.cornerRadius
        caretLayer.cornerCurve = .continuous
        caretLayer.frame = bounds
        layer?.addSublayer(caretLayer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: EmberDesign.Caret.width, height: EmberDesign.Caret.defaultHeight))
    }

    public override var wantsUpdateLayer: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: EmberDesign.Caret.width, height: lineHeight)
    }

    public override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.backgroundColor = Self.resolvedColor(for: effectiveAppearance).cgColor
        CATransaction.commit()
    }

    public override func layout() {
        super.layout()
        fitCaretLayer()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitCaretLayer()
    }

    private func fitCaretLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.frame = bounds
        CATransaction.commit()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func isAccessibilityElement() -> Bool {
        false
    }

    /// Whether motion is reduced right now (the override, else the system).
    public var reducesMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Pulses between opacity 1 and 0.3 every `Motion.caretBreathePeriod`
    /// seconds; solid under Reduce Motion. Idempotent: a running breath is
    /// not restarted.
    public func breathe() {
        caretLayer.removeAnimation(forKey: Self.fadeKey)
        setOpacity(EmberDesign.Motion.caretBreatheMaxOpacity)
        mode = .breathing
        if reducesMotion {
            caretLayer.removeAnimation(forKey: Self.breatheKey)
        } else if caretLayer.animation(forKey: Self.breatheKey) == nil {
            caretLayer.add(Self.breatheAnimation(), forKey: Self.breatheKey)
        }
    }

    /// Fully opaque and still (text is streaming).
    public func solid() {
        caretLayer.removeAnimation(forKey: Self.breatheKey)
        caretLayer.removeAnimation(forKey: Self.fadeKey)
        setOpacity(EmberDesign.Motion.caretBreatheMaxOpacity)
        mode = .solid
    }

    /// Fades to transparent over `Motion.caretFadeDuration`, then calls
    /// `completion` on the main actor.
    public func fadeOut(completion: (@MainActor () -> Void)? = nil) {
        let current = caretLayer.presentation()?.opacity ?? caretLayer.opacity
        caretLayer.removeAnimation(forKey: Self.breatheKey)
        mode = .hidden
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            Task { @MainActor in completion?() }
        }
        setOpacity(0)
        caretLayer.add(Self.fadeOutAnimation(from: current), forKey: Self.fadeKey)
        CATransaction.commit()
    }

    /// Applies `mode` (what `EAccentCaret` calls on every update); a mode
    /// already showing is left running.
    public func apply(_ mode: Mode) {
        switch mode {
        case .solid where self.mode != .solid || caretLayer.opacity != EmberDesign.Motion.caretBreatheMaxOpacity:
            solid()
        case .breathing:
            breathe()
        case .hidden where self.mode != .hidden:
            fadeOut()
        default:
            break
        }
    }

    private func setOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.opacity = opacity
        CATransaction.commit()
    }

    // MARK: Building blocks

    /// The caret colour for `appearance` (Increase Contrast aware).
    public static func resolvedColor(for appearance: NSAppearance) -> NSColor {
        var resolved = EmberDesign.Brand.nsAccentMark
        appearance.performAsCurrentDrawingAppearance {
            resolved = EmberDesign.Brand.nsAccentMark.usingColorSpace(.sRGB) ?? EmberDesign.Brand.nsAccentMark
        }
        return resolved
    }

    /// The breath: opacity 1 → 0.3 → 1, forever.
    public static func breatheAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = EmberDesign.Motion.caretBreatheMaxOpacity
        animation.toValue = EmberDesign.Motion.caretBreatheMinOpacity
        animation.duration = EmberDesign.Motion.caretBreathePeriod / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// The completion fade from `opacity` to 0.
    public static func fadeOutAnimation(from opacity: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = opacity
        animation.toValue = 0
        animation.duration = EmberDesign.Motion.caretFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
}

/// The accent caret in SwiftUI.
///
/// ```swift
/// EAccentCaret(mode: isThinking ? .breathing : .solid, height: lineHeight)
/// ```
public struct EAccentCaret: NSViewRepresentable {
    public var mode: EAccentCaretView.Mode
    /// One line of the text the caret follows.
    public var height: CGFloat

    public init(mode: EAccentCaretView.Mode = .solid, height: CGFloat = EmberDesign.Caret.defaultHeight) {
        self.mode = mode
        self.height = height
    }

    public func makeNSView(context: Context) -> EAccentCaretView {
        let view = EAccentCaretView()
        view.lineHeight = height
        return view
    }

    public func updateNSView(_ nsView: EAccentCaretView, context: Context) {
        nsView.lineHeight = height
        nsView.reduceMotionOverride = context.environment.accessibilityReduceMotion ? true : nil
        nsView.apply(mode)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: EAccentCaretView, context: Context) -> CGSize? {
        CGSize(width: EmberDesign.Caret.width, height: height)
    }
}
