import AppKit
import PIDesign

/// Draws the menu bar icon for each appearance. Every image is a template, so the menu bar tints
/// it for its own appearance and for the highlighted state.
enum StatusIconRenderer {
    enum Metrics {
        /// A menu bar glyph's size; the size the `ToolbarIcon` asset is drawn for.
        static let iconSize = NSSize(width: 18, height: 18)
        /// The attention dot, at the glyph's top-right corner…
        static let dotDiameter: CGFloat = 5
        /// …with a clear ring this wide cut around it, so it reads apart from the glyph.
        static let dotClearance: CGFloat = 1.5
        /// The checkmark shown when a run finished while the panel was hidden.
        static let checkmarkPointSize: CGFloat = 14
        /// Breathing while a run is in flight: down to this opacity and back, once per caret
        /// breath (`EmberDesign.Motion.caretBreathePeriod`).
        static let breatheMinimumOpacity: Float = 0.4
        /// How long the checkmark stays.
        static let doneDuration: Duration = .seconds(2.5)
    }

    /// The template image for `appearance`; nil only if not even the SF Symbol fallback loads.
    static func image(for appearance: StatusIconAppearance, accessibilityDescription: String) -> NSImage? {
        let base: NSImage?
        switch appearance.glyph {
        case .cursor: base = glyph()
        case .checkmark: base = checkmark()
        }
        guard let base else { return nil }
        let image = appearance.hasDot ? withDot(base) : base
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// `ToolbarIcon` from the app's asset catalog; an SF Symbol if the catalog has none (a test
    /// host, a broken build).
    static func glyph() -> NSImage? {
        if let image = NSImage(named: "ToolbarIcon")?.copy() as? NSImage {
            image.size = Metrics.iconSize
            image.isTemplate = true
            return image
        }
        let symbol = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil)
        symbol?.isTemplate = true
        return symbol
    }

    private static func checkmark() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: Metrics.checkmarkPointSize, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        // Centred on the glyph's canvas, so the item keeps its width.
        return render { rect in
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }

    /// `base` with a dot at its top-right corner and a clear ring around the dot.
    private static func withDot(_ base: NSImage) -> NSImage {
        render { rect in
            base.draw(in: aspectFit(base.size, in: rect))
            let dot = NSRect(
                x: rect.maxX - Metrics.dotDiameter,
                y: rect.maxY - Metrics.dotDiameter,
                width: Metrics.dotDiameter,
                height: Metrics.dotDiameter
            )
            guard let context = NSGraphicsContext.current else { return }
            context.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -Metrics.dotClearance, dy: -Metrics.dotClearance)).fill()
            context.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    /// `size` scaled to fit `rect`, centred.
    private static func aspectFit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Draws now, at 1× and 2×, into bitmaps: an image with a drawing handler would draw later,
    /// on whatever thread AppKit picks.
    private static func render(_ draw: (NSRect) -> Void) -> NSImage {
        let size = Metrics.iconSize
        let image = NSImage(size: size)
        for scale in [1, 2] {
            guard let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale,
                pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            // In points before the context exists, so the context scales points to pixels.
            representation.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: representation) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            draw(NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(representation)
        }
        return image
    }

    /// The breathing animation for the status button's layer.
    static func breathingAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = Float(1)
        animation.toValue = Metrics.breatheMinimumOpacity
        animation.duration = EmberDesign.Motion.caretBreathePeriod / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        return animation
    }
}
