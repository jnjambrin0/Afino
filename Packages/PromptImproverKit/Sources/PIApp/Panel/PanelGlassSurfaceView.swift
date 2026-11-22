import AppKit
import PIDesign

/// The panel's surface: system Liquid Glass (`NSGlassEffectView`, macOS 26, regular style) with
/// the content as the glass's `contentView` — the only subview AppKit guarantees to place inside
/// the glass. The glass gets a `tintColor` (`windowBackgroundColor` at `EmberDesign.Glass.tintDark`
/// or `tintLight`, by appearance) so busy backdrops stop competing with the text; vibrancy,
/// Increase Contrast, Reduce Transparency and the user's Clear/Tinted choice stay with the system.
/// Nothing else is layered on the glass: no overlay and no second material.
///
/// The glass sits inside this clipping container (layer `cornerRadius`, continuous curve,
/// `masksToBounds`). Without it, the glass's own soft shadow is cut by the window's rectangular
/// bounds and paints a faint square plate into the four corners, and the native window shadow —
/// computed by the window server from the window's alpha — comes out rectangular. With the clip,
/// everything outside the rounded shape is fully transparent, so the native shadow follows the
/// glass. The owning panel calls `invalidateShadow()` whenever the surface changes size.
final class PanelGlassSurfaceView: NSView {
    let glassView: NSGlassEffectView

    init(frame frameRect: NSRect, content: NSView, cornerRadius: CGFloat = EmberDesign.Radius.window) {
        glassView = NSGlassEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)

        glassView.style = .regular
        glassView.cornerRadius = cornerRadius
        glassView.tintColor = Self.tintColor
        glassView.autoresizingMask = [.width, .height]
        content.frame = glassView.bounds
        content.autoresizingMask = [.width, .height]
        glassView.contentView = content
        addSubview(glassView)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    /// `windowBackgroundColor` at the tint alpha for the drawing appearance (the glass resolves
    /// dynamic colours when it draws).
    static var tintColor: NSColor {
        NSColor(name: "PromptImproverGlassTint") { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.windowBackgroundColor.withAlphaComponent(EmberDesign.Glass.tintAlpha(isDark: isDark))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glassView.tintColor = Self.tintColor
    }

    /// The glass and its clip share one radius (the window's, or a confirmation pill's).
    func setCornerRadius(_ radius: CGFloat) {
        glassView.cornerRadius = radius
        layer?.cornerRadius = radius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
