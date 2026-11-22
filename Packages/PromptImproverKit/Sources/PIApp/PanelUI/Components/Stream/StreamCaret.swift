import AppKit
import PIDesign
import QuartzCore

/// The accent caret drawn by the result well: a 2 pt rounded bar in a `CALayer` (never a
/// character or an attachment), reusing `EAccentCaretView`'s colour and animations.
///
/// - `breathe(reduceMotion:)`: opacity 1 ↔ 0.3 every 1.1 s (solid under Reduce Motion).
/// - `solid()`: fully opaque and still (text is arriving).
/// - `hide()`: fades out over 180 ms.
final class StreamCaret {
    enum State: Equatable {
        case hidden
        case solid
        case breathing
    }

    let layer = CALayer()
    private(set) var state: State = .hidden

    init() {
        // No implicit animations: the caret moves with the text, exactly.
        let none = NSNull()
        layer.actions = [
            "position": none, "bounds": none, "frame": none, "opacity": none,
            "backgroundColor": none, "hidden": none, "cornerRadius": none,
        ]
        layer.cornerRadius = EmberDesign.Caret.cornerRadius
        layer.cornerCurve = .continuous
        layer.opacity = 0
        // Above the text's own layers.
        layer.zPosition = 1
    }

    var frame: CGRect {
        get { layer.frame }
        set { layer.frame = newValue }
    }

    /// Resolves the accent for `appearance`: a layer's `CGColor` does not follow appearance
    /// changes on its own.
    func setColor(for appearance: NSAppearance) {
        layer.backgroundColor = EAccentCaretView.resolvedColor(for: appearance).cgColor
    }

    func breathe(reduceMotion: Bool) {
        layer.removeAnimation(forKey: Self.fadeKey)
        layer.opacity = EmberDesign.Motion.caretBreatheMaxOpacity
        state = .breathing
        if reduceMotion {
            layer.removeAnimation(forKey: Self.breatheKey)
        } else if layer.animation(forKey: Self.breatheKey) == nil {
            layer.add(EAccentCaretView.breatheAnimation(), forKey: Self.breatheKey)
        }
    }

    func solid() {
        layer.removeAnimation(forKey: Self.breatheKey)
        layer.removeAnimation(forKey: Self.fadeKey)
        layer.opacity = EmberDesign.Motion.caretBreatheMaxOpacity
        state = .solid
    }

    func hide() {
        guard state != .hidden else { return }
        let current = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: Self.breatheKey)
        state = .hidden
        layer.opacity = 0
        layer.add(EAccentCaretView.fadeOutAnimation(from: current), forKey: Self.fadeKey)
    }

    private static let breatheKey = "stream.caret.breathe"
    private static let fadeKey = "stream.caret.fade"
}
