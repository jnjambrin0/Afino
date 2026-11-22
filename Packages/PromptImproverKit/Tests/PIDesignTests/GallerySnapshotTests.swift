import AppKit
import SwiftUI
import Testing
@testable import PIDesign

/// Renders `EmberGallery` light and dark through the window server, so the Liquid Glass shows,
/// for a person to compare after a kit change. Opt-in: `PI_GALLERY_SNAPSHOTS=<folder> swift test
/// --filter GallerySnapshotTests`. It checks nothing by itself.
@MainActor
struct GallerySnapshotTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["PI_GALLERY_SNAPSHOTS"].map { URL(filePath: $0) }

    @Test(.enabled(if: folder != nil))
    func renderGallery() async throws {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for dark in [false, true] {
            let host = NSHostingView(rootView: EmberGallery())
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(700))
            window.displayIfNeeded()
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), folder.appending(path: "gallery-\(dark ? "dark" : "light").png").path]
            try process.run()
            process.waitUntilExit()
            window.orderOut(nil)
        }
    }
}
