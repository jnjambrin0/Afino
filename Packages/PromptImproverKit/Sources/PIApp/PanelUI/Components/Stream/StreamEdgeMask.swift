import AppKit
import PIDesign
import QuartzCore

/// The soft edge of a scrolled well: an alpha mask that fades the content over
/// `EmberDesign.Stream.edgeFade` points, only on an edge where content is clipped.
enum StreamEdgeMask {
    /// Fade heights for a viewport `clipHeight` tall showing `offset…offset + clipHeight` of a
    /// document `documentHeight` tall. Each grows with the clipped amount (up to the token), so
    /// the fade never pops in.
    nonisolated static func fades(documentHeight: CGFloat, clipHeight: CGFloat, offset: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let limit = EmberDesign.Stream.edgeFade
        let top = min(max(offset, 0), limit)
        let bottom = min(max(documentHeight - (offset + clipHeight), 0), limit)
        let half = max(clipHeight / 2, 0)
        return (min(top, half), min(bottom, half))
    }

    /// The gradient stops (top to bottom) for those fades: transparent at a clipped edge,
    /// opaque everywhere else.
    nonisolated static func stops(height: CGFloat, top: CGFloat, bottom: CGFloat) -> (locations: [Double], alphas: [CGFloat]) {
        guard height > 0 else { return ([0, 1], [1, 1]) }
        let topEnd = Double(top / height)
        let bottomStart = Double(1 - bottom / height)
        return (
            [0, topEnd, bottomStart, 1],
            [top > 0 ? 0 : 1, 1, 1, bottom > 0 ? 0 : 1]
        )
    }

    /// Updates `mask` (a gradient layer covering `bounds` of a view) for the given fades.
    /// `flipped`: the masked layer's y axis points down.
    static func update(_ mask: CAGradientLayer, bounds: CGRect, top: CGFloat, bottom: CGFloat, flipped: Bool) {
        let stops = stops(height: bounds.height, top: top, bottom: bottom)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.colors = stops.alphas.map { CGColor(gray: 0, alpha: $0) }
        mask.locations = stops.locations.map { NSNumber(value: $0) }
        mask.startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        mask.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
        CATransaction.commit()
    }
}
