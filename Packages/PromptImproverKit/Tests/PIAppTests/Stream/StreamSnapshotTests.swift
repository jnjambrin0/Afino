import AppKit
@testable import PIApp
import PIDesign
import Testing

/// Opt-in visual check of the result well. Opens real windows (light and dark), streams into a
/// `StreamTextView` and captures each window on its own with `screencapture -l`, so Core
/// Animation compositing (the caret layer, the edge mask, the glass capsule) is in the picture.
/// Writes numbered PNGs for a person to look at; the edge-fade tests also measure their
/// captures. Run with:
///
///     PI_STREAM_SNAPSHOT_DIR=/some/folder swift test --filter StreamSnapshotTests
///
/// Skipped unless the variable is set: it puts windows on screen and needs the terminal to be
/// allowed to record the screen.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PI_STREAM_SNAPSHOT_DIR"] != nil))
struct StreamSnapshotTests {
    private typealias Support = StreamTestSupport

    private static var directory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PI_STREAM_SNAPSHOT_DIR"] ?? NSTemporaryDirectory(), directoryHint: .isDirectory)
    }

    private static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    private static let outerPadding: CGFloat = 12
    private static let wellWidth: CGFloat = 660

    /// A window with a well (a solid sheet, like the panel's) and the view inside it.
    private func makeWindow(height: CGFloat, appearance: NSAppearance.Name) -> (NSWindow, StreamTextView) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let padding = Self.outerPadding
        let size = NSSize(width: Self.wellWidth + padding * 2, height: height + padding * 2)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 60, y: 120), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let well = NSView(frame: NSRect(x: padding, y: padding, width: Self.wellWidth, height: height))
        well.wantsLayer = true
        var fill = NSColor.textBackgroundColor.cgColor
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            fill = NSColor.textBackgroundColor.cgColor
        }
        well.layer?.backgroundColor = fill
        well.layer?.cornerRadius = EmberDesign.Radius.well
        let view = StreamTextView(frame: well.bounds)
        view.autoresizingMask = [.width, .height]
        view.reduceMotionOverride = false
        well.addSubview(view)
        container.addSubview(well)
        window.contentView = container
        window.orderFrontRegardless()
        Support.pump(timeout: 0.1)
        return (window, view)
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.directory.appending(path: "\(name).png")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        // The main thread waits here, so nothing new is committed: the capture shows the last frame.
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func emptyWellWithABreathingCaret() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: EmberDesign.Panel.wellMinHeight, appearance: appearance)
            defer { window.close() }
            view.setText("", streaming: false)
            view.caretMode = .breathing
            Support.pump(timeout: 0.15)
            try capture(window, "1-empty-breathing-\(label)")
        }
    }

    @Test func midStreamWithFadingRunsAndTrailingCaret() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: 330, appearance: appearance)
            defer { window.close() }
            view.caretMode = .trailing
            let cut = Support.prompt.unicodeScalars.index(Support.prompt.unicodeScalars.startIndex, offsetBy: 300)
            let partial = String(Support.prompt.unicodeScalars[..<cut])
            Support.stream(partial, into: view, maxChunk: 30, pause: 0.02)
            // Stop right after a release, while runs are still fading in.
            Support.pump(timeout: 1) { Support.hasFadingText(view) && view.hasPendingText }
            try capture(window, "2-midstream-\(label)")
        }
    }

    @Test func finishedTextWithSyntaxTint() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: 420, appearance: appearance)
            defer { window.close() }
            view.caretMode = .trailing
            Support.stream(Support.prompt, into: view, maxChunk: 60, pause: 0.01)
            view.finishStreaming()
            view.caretMode = .hidden
            Support.pump(timeout: 1) { !view.hasPendingText && !Support.hasFadingText(view) }
            Support.pump(timeout: 0.3)
            try capture(window, "3-final-\(label)")
        }
    }

    @Test func pinnedAtTheBottomWithATopEdgeFade() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: 150, appearance: appearance)
            defer { window.close() }
            view.caretMode = .trailing
            Support.stream(Support.prompt, into: view, maxChunk: 40, pause: 0.015)
            Support.pump(timeout: 1.5) { !view.hasPendingText && abs(view.scrollOffset - view.maximumScrollOffset) < 1 }
            Support.pump(timeout: 0.1)
            try capture(window, "4-pinned-\(label)")
        }
    }

    @Test func scrolledAwayWithJumpToLatest() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: 150, appearance: appearance)
            defer { window.close() }
            view.caretMode = .trailing
            let cut = Support.prompt.unicodeScalars.index(Support.prompt.unicodeScalars.startIndex, offsetBy: 330)
            Support.stream(String(Support.prompt.unicodeScalars[..<cut]), into: view, maxChunk: 40, pause: 0.015)
            Support.pump(timeout: 1.5) { !view.hasPendingText && abs(view.scrollOffset - view.maximumScrollOffset) < 1 }
            for _ in 0..<3 {
                view.scrollLine(down: false)
            }
            view.setText(Support.prompt, streaming: true)
            Support.pump(timeout: 0.6) { !view.hasPendingText }
            Support.pump(timeout: 0.3)
            #expect(view.isShowingJumpToLatest)
            try capture(window, "5-detached-\(label)")
        }
    }

    /// Dense text scrolled to the middle: both edges are clipped, so both fade. Measures it: in
    /// light mode the darkest ink in the outer rows of each edge must be clearly lighter than in
    /// the rows inside.
    @Test func bothEdgesFadeWhereContentIsClipped() throws {
        for (label, appearance) in Self.appearances {
            let (window, view) = makeWindow(height: 150, appearance: appearance)
            defer { window.close() }
            let lines = (1...30).map { "Line \($0): the quick brown fox jumps over the lazy dog, again and again." }.joined(separator: "\n")
            view.setText(lines, streaming: false)
            view.scrollToEnd()
            for _ in 0..<12 {
                view.scrollLine(down: false)
            }
            Support.pump(timeout: 0.2)
            let name = "6-edges-\(label)"
            try capture(window, name)
            guard label == "light" else { continue }
            let ink = try edgeInk(window, name)
            print("Edge ink, both edges clipped: \(ink)")
            #expect(ink.top > ink.inside + 0.3, "the top edge should fade")
            #expect(ink.bottom > ink.inside + 0.3, "the bottom edge should fade")
        }
    }

    /// One clipped edge at a time, so the mask's orientation is proven: at the top of a long text
    /// only the bottom fades; at its end only the top does.
    @Test func onlyTheClippedEdgeFades() throws {
        let (window, view) = makeWindow(height: 150, appearance: .aqua)
        defer { window.close() }
        let lines = (1...30).map { "Line \($0): the quick brown fox jumps over the lazy dog, again and again." }.joined(separator: "\n")
        view.setText(lines, streaming: false)
        Support.pump(timeout: 0.2)
        #expect(view.scrollOffset == 0)
        try capture(window, "7-top-of-text-light")
        let atTop = try edgeInk(window, "7-top-of-text-light")
        print("Edge ink at the top of the text: \(atTop)")
        #expect(atTop.bottom > atTop.inside + 0.3, "the clipped bottom edge should fade")

        // The end, with a line clipped at the top: align the offset to cut through a line.
        view.scrollToEnd()
        view.scrollLine(down: false)
        view.scrollToEnd()
        Support.pump(timeout: 0.2)
        try capture(window, "8-end-of-text-light")
        let atEnd = try edgeInk(window, "8-end-of-text-light")
        print("Edge ink at the end of the text: \(atEnd)")
        #expect(atEnd.top > atEnd.inside + 0.3, "the clipped top edge should fade")
    }

    /// The darkest ink (brightness, light mode) in the outer third of each fade zone, and inside.
    private func edgeInk(_ window: NSWindow, _ name: String) throws -> (top: CGFloat, inside: CGFloat, bottom: CGFloat) {
        let data = try Data(contentsOf: Self.directory.appending(path: "\(name).png"))
        let image = try #require(NSBitmapImageRep(data: data))
        let scale = CGFloat(image.pixelsHigh) / window.frame.height
        let wellTop = Int(Self.outerPadding * scale)
        let wellBottom = image.pixelsHigh - Int(Self.outerPadding * scale)
        let fade = Int(EmberDesign.Stream.edgeFade * scale)
        func darkest(_ rows: Range<Int>) -> CGFloat {
            var value: CGFloat = 1
            for y in rows {
                for x in Int(40 * scale)..<Int(500 * scale) {
                    if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                        value = min(value, color.brightnessComponent)
                    }
                }
            }
            return value
        }
        return (
            darkest(wellTop..<(wellTop + fade / 3)),
            darkest((wellTop + fade * 2)..<(wellBottom - fade * 2)),
            darkest((wellBottom - fade / 3)..<wellBottom)
        )
    }
}
