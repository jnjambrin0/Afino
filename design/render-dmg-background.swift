// Renders the background of the installer window (the DMG) and writes it where the release
// pipeline reads it.
//
//   xcrun swift design/render-dmg-background.swift [output-directory]
//
// Run from the repository root. Writes `dmg-background.tiff` (660 × 420 pt, @1x and @2x in one
// HiDPI TIFF made with `tiffutil -cathidpicheck`) to `scripts/release/dmg-assets/` unless another
// directory is given. The output is deterministic: an unchanged script reproduces the committed
// file byte for byte.
//
// The layout matches `scripts/release/dmg-assets/dmg-settings.py`: a 660 × 420 pt window with the
// 128 pt icons centred at (175, 175) and (485, 175). The fill is a mid tone on purpose: Finder draws
// icon labels black in light mode and white in dark mode, and both must read.
import AppKit

func render(scale: CGFloat) -> Data {
    let w = 660, h = 420
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(w) * scale), pixelsHigh: Int(CGFloat(h) * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a) }
    NSGradient(starting: c(0x3BA99A), ending: c(0x2A8C7F))!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -70)
    // The arrow between the two icons, at their centre line (AppKit's y grows upward).
    let y: CGFloat = 420 - 175
    let line = NSBezierPath(); line.move(to: NSPoint(x: 272, y: y)); line.line(to: NSPoint(x: 386, y: y))
    line.lineWidth = 3; line.lineCapStyle = .round
    NSGraphicsContext.current!.cgContext.saveGState()
    let cg = NSGraphicsContext.current!.cgContext
    cg.addPath(line.cgPath); cg.setLineWidth(3); cg.setLineCap(.round); cg.replacePathWithStrokedPath(); cg.clip()
    NSGradient(starting: c(0xFFFFFF, 0), ending: c(0xFFFFFF, 0.95))!.draw(in: NSRect(x: 264, y: y - 4, width: 128, height: 8), angle: 0)
    cg.restoreGState()
    let head = NSBezierPath(); head.move(to: NSPoint(x: 376, y: y + 11)); head.line(to: NSPoint(x: 389, y: y)); head.line(to: NSPoint(x: 376, y: y - 11))
    head.lineWidth = 3; head.lineCapStyle = .round; head.lineJoinStyle = .round; c(0xFFFFFF, 0.95).setStroke(); head.stroke()
    // The caption sits well below the icons, so it stays visible when Finder shows its path bar.
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let text = NSAttributedString(string: "Drag Afino to Applications", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: c(0xFFFFFF, 0.92), .paragraphStyle: style])
    text.draw(in: NSRect(x: 0, y: 420 - 318, width: 660, height: 20))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "scripts/release/dmg-assets", isDirectory: true)
let work = fm.temporaryDirectory.appendingPathComponent("afino-dmg-background-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try! fm.createDirectory(at: work, withIntermediateDirectories: true)
try! fm.createDirectory(at: output, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }

try! render(scale: 1).write(to: work.appendingPathComponent("dmg-background.png"))
try! render(scale: 2).write(to: work.appendingPathComponent("dmg-background@2x.png"))

// Relative names on purpose: tiffutil records the first input's name in the TIFF.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.currentDirectoryURL = work
tiffutil.arguments = ["-cathidpicheck", "dmg-background.png", "dmg-background@2x.png", "-out", "dmg-background.tiff"]
tiffutil.standardOutput = FileHandle.nullDevice
try! tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { print("tiffutil failed"); exit(1) }

let destination = output.appendingPathComponent("dmg-background.tiff")
try? fm.removeItem(at: destination)
try! fm.copyItem(at: work.appendingPathComponent("dmg-background.tiff"), to: destination)
print("Wrote \(destination.path)")
