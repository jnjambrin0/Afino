// Composes the images in docs/images from raw captures, so they can be redone after a UI change.
//
//   design/capture-screenshots.sh                         raw window captures → build/screenshots/
//   xcrun swift design/generate-icons.swift --previews    icon renders        → build/icon-previews/
//   xcrun swift design/render-doc-images.swift            composed images     → docs/images/
//
// Run from the repository root. Each image is made only when its inputs exist, so either half can
// be refreshed on its own. Screenshots are placed at their captured pixel size (never scaled, so
// text stays sharp) on the same dark, aquamarine-tinted backdrop with one shadow recipe; the
// output is sRGB PNG.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
guard fm.fileExists(atPath: "PromptImprover.xcodeproj") else {
    print("Run from the repository root.")
    exit(1)
}
let screenshots = URL(fileURLWithPath: "build/screenshots", isDirectory: true)
let iconPreviews = URL(fileURLWithPath: "build/icon-previews", isDirectory: true)
let output = URL(fileURLWithPath: "docs/images", isDirectory: true)
try! fm.createDirectory(at: output, withIntermediateDirectories: true)

// MARK: - Helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// An sRGB canvas, y up. Captures in other colour spaces (Display P3, a monitor's profile) are
/// converted as they are drawn.
func canvas(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

func save(_ context: CGContext, _ name: String) {
    let url = output.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
    let bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("docs/images/\(name)  \(context.width) × \(context.height)  \(bytes / 1024) KB")
}

/// Text in AppKit, drawn into a Core Graphics canvas.
func drawText(_ text: String, in context: CGContext, centeredAt center: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color)!,
    ])
    let bounds = attributed.size()
    attributed.draw(at: CGPoint(x: (center.x - bounds.width / 2).rounded(), y: (center.y - bounds.height / 2).rounded()))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Backdrop and window

/// Deep teal at the top to near-black at the bottom, a faint glow of the accent (#51D7C2) behind
/// the window, rounded corners and a hairline rim so the image reads on a light or a dark page.
///
/// The gradients are drawn at an eighth of the size, in 16 bits per channel, and scaled up: smooth
/// ramps without dithering noise, which keeps the PNG small.
func drawBackdrop(_ context: CGContext, glowCenter: CGPoint, glowRadius: CGFloat, glowAlpha: CGFloat, cornerRadius: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
    let factor: CGFloat = 8
    let small = CGContext(
        data: nil, width: Int((rect.width / factor).rounded(.up)), height: Int((rect.height / factor).rounded(.up)),
        bitsPerComponent: 16, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    small.scaleBy(x: 1 / factor, y: 1 / factor)
    let base = CGGradient(colorsSpace: sRGB, colors: [rgb(0x163B37), rgb(0x0C2321), rgb(0x061211)] as CFArray, locations: [0, 0.5, 1])!
    small.drawLinearGradient(base, start: CGPoint(x: rect.width * 0.35, y: rect.height), end: CGPoint(x: rect.width * 0.65, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: sRGB, colors: [rgb(0x51D7C2, glowAlpha), rgb(0x51D7C2, glowAlpha * 0.4), rgb(0x51D7C2, 0)] as CFArray, locations: [0, 0.4, 1])!
    small.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: glowRadius, options: [])

    let shape = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: CGFloat(small.width) * factor, height: CGFloat(small.height) * factor))
    context.restoreGState()

    context.saveGState()
    let inset = rect.insetBy(dx: 1, dy: 1)
    context.addPath(CGPath(roundedRect: inset, cornerWidth: cornerRadius - 1, cornerHeight: cornerRadius - 1, transform: nil))
    context.setStrokeColor(rgb(0xFFFFFF, 0.07))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()
}

/// A window capture (taken without its shadow) with a soft ambient shadow and a tighter contact
/// shadow, the way macOS lights a floating panel.
func drawWindow(_ context: CGContext, _ image: CGImage, origin: CGPoint) {
    let rect = CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: CGFloat(image.width), height: CGFloat(image.height))
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -40), blur: 120, color: rgb(0x000000, 0.6))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: rgb(0x000000, 0.45))
    context.draw(image, in: rect)
    context.endTransparencyLayer()
    context.restoreGState()
}

/// One capture centred on a backdrop of `width`, with `top` and `bottom` margins.
func compose(_ capture: String, into name: String, width: Int, top: Int, bottom: Int, glowAlpha: CGFloat, cornerRadius: CGFloat) {
    guard let image = load(screenshots.appendingPathComponent("\(capture).png")) else { return }
    let height = image.height + top + bottom
    let context = canvas(width, height)
    let origin = CGPoint(x: CGFloat(width - image.width) / 2, y: CGFloat(bottom))
    let glowCenter = CGPoint(x: CGFloat(width) / 2, y: origin.y + CGFloat(image.height) * 0.62)
    drawBackdrop(context, glowCenter: glowCenter, glowRadius: CGFloat(max(width, height)) * 0.6, glowAlpha: glowAlpha, cornerRadius: cornerRadius)
    drawWindow(context, image, origin: origin)
    save(context, name)
}

// MARK: - README screenshots

// The hero: a finished result, large.
compose("result", into: "hero.png", width: 2400, top: 250, bottom: 300, glowAlpha: 0.30, cornerRadius: 44)

// Supporting images: one width, one set of margins.
for (capture, name) in [
    ("target-menu", "target-menu.png"),
    ("refine", "refine.png"),
    ("history", "history.png"),
    ("settings-engine", "settings-engine.png"),
] {
    compose(capture, into: name, width: 1800, top: 130, bottom: 170, glowAlpha: 0.24, cornerRadius: 36)
}

// MARK: - Icon images

/// The app icon as macOS shows it: the tile at 824/1024 of the canvas, with a soft shadow.
if let icon = load(iconPreviews.appendingPathComponent("icon-default-1024.png")) {
    let size = 512
    let context = canvas(size, size)
    let tile = CGFloat(size) * 824 / 1024
    let rect = CGRect(x: (CGFloat(size) - tile) / 2, y: (CGFloat(size) - tile) / 2 + 6, width: tile, height: tile)
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x000000, 0.32))
    context.draw(icon, in: rect)
    save(context, "app-icon.png")
}

/// Every appearance the system renders the icon in: the light ones over a light desktop, the dark
/// ones over a dark desktop.
let renditions: [[(file: String, label: String)]] = [
    [("default", "Default"), ("tintedlight", "Tinted (light)"), ("clearlight", "Clear (light)")],
    [("dark", "Dark"), ("tinteddark", "Tinted (dark)"), ("cleardark", "Clear (dark)")],
]
let renders = renditions.map { row in row.map { load(iconPreviews.appendingPathComponent("icon-\($0.file)-1024.png")) } }
if renders.allSatisfy({ $0.allSatisfy { $0 != nil } }) {
    let tile = 240, gap = 120, labelSpace = 64, pad = 70
    let width = pad * 2 + tile * 3 + gap * 2
    let rowHeight = pad + tile + labelSpace
    let context = canvas(width, rowHeight * 2)
    let shape = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: rowHeight * 2), cornerWidth: 36, cornerHeight: 36, transform: nil)
    context.addPath(shape)
    context.clip()
    for (rowIndex, row) in renditions.enumerated() {
        let isDark = rowIndex == 1
        let y = CGFloat(isDark ? 0 : rowHeight)
        context.setFillColor(isDark ? rgb(0x1E1E21) : rgb(0xE6E6EB))
        context.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: CGFloat(rowHeight)))
        for (column, item) in row.enumerated() {
            let x = CGFloat(pad + column * (tile + gap))
            let iconRect = CGRect(x: x, y: y + CGFloat(labelSpace), width: CGFloat(tile), height: CGFloat(tile))
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -5), blur: 14, color: rgb(0x000000, isDark ? 0.5 : 0.22))
            context.draw(renders[rowIndex][column]!, in: iconRect)
            context.restoreGState()
            drawText(item.label, in: context, centeredAt: CGPoint(x: iconRect.midX, y: y + CGFloat(labelSpace) / 2 + 2),
                     size: 22, weight: .medium, color: isDark ? rgb(0xFFFFFF, 0.72) : rgb(0x000000, 0.62))
        }
    }
    save(context, "icon-appearances.png")
}
