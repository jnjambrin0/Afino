import AppKit
import ApplicationServices
import CoreImage
import CoreMedia
@testable import PIApp
import PIDesign
import ScreenCaptureKit
import SwiftUI
import Testing

/// Operates a real Settings window the way a person would, without touching the user's pointer
/// or keyboard, for the opt-in `SettingsInteractionSnapshotTests`. Controls are found through the
/// window's accessibility tree (as VoiceOver reads it) and receive synthesized events sent
/// straight to the window, which reports itself key so it draws and behaves as the front window
/// while the app the user is in stays active. Captures come from the window server, so Liquid
/// Glass shows as it does on screen.
@MainActor
final class SettingsWindowDriver {
    let window: NSWindow
    let folder: URL

    init(window: NSWindow, folder: URL) {
        self.window = window
        self.folder = folder
        window.acceptsMouseMovedEvents = true
    }

    // MARK: Window

    /// Accessibility settings the window is drawn with (SwiftUI's own overrides; Liquid Glass
    /// itself follows the system setting).
    struct Overrides {
        var reduceMotion = false
        var reduceTransparency = false
        var increaseContrast = false
    }

    /// A Settings window for `fixture`, configured like `SettingsWindowController`'s, on screen at a
    /// fixed place. `appearance` may be an Increase Contrast appearance.
    static func settingsWindow(
        _ fixture: SettingsFixture,
        appearance: NSAppearance.Name,
        overrides: Overrides = Overrides()
    ) -> NSWindow {
        let root = SettingsRootView(model: fixture.model, context: fixture.context)
            .environment(\._accessibilityReduceMotion, overrides.reduceMotion)
            .environment(\._accessibilityReduceTransparency, overrides.reduceTransparency)
            .environment(\._colorSchemeContrast, overrides.increaseContrast ? .increased : .standard)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let window = AlwaysKeyWindow(
            contentRect: NSRect(origin: .zero, size: EmberDesign.Settings.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "SettingsWindowDriverToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.setContentSize(EmberDesign.Settings.windowSize)
        // `elements()` finds the window in the accessibility tree by this title.
        window.title = "Settings Window Driver"
        window.appearance = NSAppearance(named: appearance)
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        // As `SettingsWindowController.show` does: nothing starts focused.
        window.makeFirstResponder(nil)
        return window
    }

    // MARK: Run loop

    /// Lets AppKit and SwiftUI run (layout, display, animations) for `seconds`. Work the views
    /// start with `Task { }` on the main actor waits for `wait(_:)`.
    func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(1.0 / 120)))
        }
    }

    /// Like `spin`, but also yields the main actor between frames, so tasks the views started
    /// (a key check, clearing the history) run as they would in the app.
    func wait(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            spin(1.0 / 120)
            await Task.yield()
        }
    }

    // MARK: Finding controls

    /// One element of the window's accessibility tree.
    struct Element: Sendable, CustomStringConvertible {
        let role: String
        let subrole: String
        let label: String
        let value: String
        let help: String
        /// Screen coordinates, top-left origin (AX).
        let frame: CGRect
        let depth: Int
        let isEnabled: Bool

        var description: String {
            let flags = isEnabled ? "" : " [disabled]"
            let shownValue = value.isEmpty ? "" : " = \(value)"
            let shownSubrole = subrole.isEmpty ? "" : "/\(subrole)"
            let shownHelp = help.isEmpty ? "" : " (help: \(help))"
            return "\(String(repeating: "  ", count: depth))\(role)\(shownSubrole) “\(label)”\(shownValue)\(shownHelp)\(flags) @ \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))"
        }
    }

    /// The window's accessibility tree through the AX API, as VoiceOver reads it. AX calls into
    /// this process are answered directly on the calling thread, so this runs on the main thread
    /// like any accessibility request.
    func elements() -> [Element] {
        let app = AXUIElementCreateApplication(getpid())
        guard let windows: [AXUIElement] = Self.attribute(app, kAXWindowsAttribute) else { return [] }
        let match = windows.first { (Self.attribute($0, kAXTitleAttribute) as String?) == window.title }
        guard let root = match ?? windows.first else { return [] }
        var result: [Element] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40 else { return }
            let role: String = Self.attribute(element, kAXRoleAttribute) ?? "?"
            let subrole: String = Self.attribute(element, kAXSubroleAttribute) ?? ""
            let label: String = Self.attribute(element, kAXDescriptionAttribute) ?? Self.attribute(element, kAXTitleAttribute) ?? ""
            let value: String
            if let text: String = Self.attribute(element, kAXValueAttribute) {
                value = text
            } else if let number: NSNumber = Self.attribute(element, kAXValueAttribute) {
                value = number.stringValue
            } else {
                value = ""
            }
            let help: String = Self.attribute(element, kAXHelpAttribute) ?? ""
            var origin = CGPoint.zero
            var size = CGSize.zero
            if let position: AXValue = Self.attribute(element, kAXPositionAttribute) { AXValueGetValue(position, .cgPoint, &origin) }
            if let extent: AXValue = Self.attribute(element, kAXSizeAttribute) { AXValueGetValue(extent, .cgSize, &size) }
            let enabled: Bool = Self.attribute(element, kAXEnabledAttribute) ?? true
            result.append(Element(
                role: role, subrole: subrole, label: label, value: value, help: help,
                frame: CGRect(origin: origin, size: size), depth: depth, isEnabled: enabled
            ))
            for child: AXUIElement in Self.attribute(element, kAXChildrenAttribute) ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return result
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// The first element labelled (or valued) `label`, optionally with `role`.
    func element(_ label: String, role: String? = nil) -> Element? {
        elements().first { ($0.label == label || $0.value == label) && (role == nil || $0.role == role) }
    }

    func writeOutline(_ name: String) throws {
        try elements().map(\.description).joined(separator: "\n")
            .write(to: folder.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
    }

    /// An AX (screen, top-left) frame in window coordinates.
    func windowRect(_ frame: CGRect) -> NSRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = NSRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        return window.convertFromScreen(flipped)
    }

    /// `label`'s element in window points, top-left origin (for capture regions).
    func topLeftRect(of label: String, role: String? = nil) throws -> CGRect {
        let found = try #require(element(label, role: role), "no element “\(label)”")
        let rect = windowRect(found.frame)
        let height = window.contentView?.bounds.height ?? window.frame.height
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The centre of `label`'s element in window coordinates (asked fresh: layout moves).
    func point(of label: String, role: String? = nil, offset: CGPoint = .zero) throws -> NSPoint {
        let found = try #require(element(label, role: role), "no element “\(label)”")
        let rect = windowRect(found.frame)
        return NSPoint(x: rect.midX + offset.x, y: rect.midY + offset.y)
    }

    // MARK: Events

    /// Moves the (virtual) pointer: the window gets the event, and every tracking area under or
    /// left by the point gets the entered/moved/exited calls the window server would send.
    func move(to point: NSPoint) {
        send(.mouseMoved, at: point)
        guard let root = window.contentView else { return }
        for (view, area) in trackingAreas(in: root) {
            let local = view.convert(point, from: nil)
            let rect = area.options.contains(.inVisibleRect) ? view.visibleRect : area.rect
            let inside = rect.contains(local)
            let id = ObjectIdentifier(area)
            guard let owner = area.owner as? NSResponder else { continue }
            if inside, !insideAreas.contains(id) {
                insideAreas.insert(id)
                if let event = enterExitEvent(.mouseEntered, at: point, area: area) { owner.mouseEntered(with: event) }
            } else if !inside, insideAreas.contains(id) {
                insideAreas.remove(id)
                if let event = enterExitEvent(.mouseExited, at: point, area: area) { owner.mouseExited(with: event) }
            }
            if inside, area.options.contains(.mouseMoved), let event = mouseEvent(.mouseMoved, at: point) {
                owner.mouseMoved(with: event)
            }
        }
    }

    /// An entered/exited event that names its tracking area, as the window server's do.
    private func enterExitEvent(_ type: NSEvent.EventType, at point: NSPoint, area: NSTrackingArea) -> NSEvent? {
        let pointer = Unmanaged.passUnretained(area).toOpaque()
        return NSEvent.enterExitEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: Int(bitPattern: pointer),
            userData: pointer
        )
    }

    private var insideAreas: Set<ObjectIdentifier> = []

    private func trackingAreas(in view: NSView) -> [(NSView, NSTrackingArea)] {
        view.trackingAreas.map { (view, $0) } + view.subviews.flatMap { trackingAreas(in: $0) }
    }

    func mouseDown(at point: NSPoint) {
        send(.leftMouseDown, at: point)
    }

    func mouseUp(at point: NSPoint) {
        send(.leftMouseUp, at: point)
    }

    /// Moves away, so no hover state remains.
    func moveAway() {
        move(to: NSPoint(x: 4, y: 4))
    }

    func click(_ point: NSPoint) {
        move(to: point)
        spin(0.03)
        mouseDown(at: point)
        spin(0.06)
        mouseUp(at: point)
    }

    func click(_ label: String, role: String? = nil) throws {
        click(try point(of: label, role: role))
    }

    enum Key {
        case escape
        case down
        /// ⌘ and a character, as a menu key equivalent.
        case command(String)
        /// Each character typed in turn.
        case text(String)
    }

    func press(_ key: Key) {
        switch key {
        case .escape: keyEvent("\u{1b}", code: 53)
        case .down: keyEvent(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125, modifiers: [.numericPad, .function])
        case .command(let character): keyEvent(character, code: 0, modifiers: .command)
        case .text(let text):
            for character in text { keyEvent(String(character), code: 0) }
        }
    }

    private func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: code
            )
            guard let event else { continue }
            if modifiers.contains(.command), type == .keyDown, window.performKeyEquivalent(with: event) { continue }
            window.sendEvent(event)
            spin(0.02)
        }
    }

    /// Through the application, as the window server's events arrive, so local event monitors
    /// (a floating card's outside-click watch) see them too.
    private func send(_ type: NSEvent.EventType, at point: NSPoint) {
        if let event = mouseEvent(type, at: point) { NSApp.sendEvent(event) }
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: type == .mouseMoved ? 0 : 1,
            pressure: type == .leftMouseDown ? 1 : 0
        )
    }

    /// SwiftUI's stand-ins for its focusable controls in the window's key view loop (what Tab
    /// moves through with Full Keyboard Access on), in window order. Focusing them directly shows
    /// each focus ring without turning Full Keyboard Access on for the user.
    func focusableControls() -> [NSView] {
        func proxies(_ view: NSView) -> [NSView] {
            let mine = String(describing: type(of: view)).contains("KeyViewProxy") ? [view] : []
            return mine + view.subviews.flatMap(proxies)
        }
        return window.contentView.map(proxies) ?? []
    }

    /// Gives keyboard focus to the focusable control at `index`, as Tab would.
    @discardableResult
    func focusControl(_ index: Int) -> Bool {
        let controls = focusableControls()
        guard controls.indices.contains(index) else { return false }
        let accepted = window.makeFirstResponder(controls[index])
        spin(0.2)
        return accepted
    }

    /// Scrolls the pane's scroll view to its end (or back to the top).
    func scrollPane(toEnd: Bool) {
        guard let scrollView = scrollViews(in: window.contentView).max(by: { $0.frame.height < $1.frame.height }),
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxY = max(document.frame.height - clip.bounds.height, 0)
        let y = toEnd ? (document.isFlipped ? maxY : 0) : (document.isFlipped ? 0 : maxY)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
        spin(0.2)
    }

    private func scrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        var found = view.subviews.flatMap { scrollViews(in: $0) }
        if let scrollView = view as? NSScrollView, !(scrollView.documentView is NSTextView) { found.append(scrollView) }
        return found
    }

    // MARK: Capture

    /// The window as the window server composites it.
    func capture(_ name: String) throws {
        spin(0.05)
        window.displayIfNeeded()
        let url = folder.appending(path: "\(name).png")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
    }

    /// Records the window alone (windows on top of it do not matter) at the display's rate while
    /// `drive` runs, one PNG per frame named by its time in milliseconds, into `<name>/`.
    /// `region` (window points, top-left origin) crops the frames; `scale` 1 halves the size.
    func record(_ name: String, region: CGRect? = nil, scale: CGFloat? = nil, drive: () async throws -> Void) async throws {
        let directory = folder.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let target = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) }, "window not shareable")
        let configuration = SCStreamConfiguration()
        let factor = scale ?? window.backingScaleFactor
        let crop = region ?? CGRect(origin: .zero, size: window.frame.size)
        configuration.sourceRect = crop
        configuration.width = Int(crop.width * factor)
        configuration.height = Int(crop.height * factor)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.showsCursor = false
        configuration.queueDepth = 8
        let writer = CaptureFrameWriter(directory: directory)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration, delegate: nil)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        spin(0.25)
        writer.markStart()
        try await drive()
        await wait(0.15)
        try await stream.stopCapture()
        writer.queue.sync {}
    }
}

/// Writes every complete frame of a stream as a PNG named by its time since `markStart()`.
private nonisolated final class CaptureFrameWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "SettingsWindowDriver.frames")
    private let directory: URL
    private let context = CIContext()
    private var start: CMTime?
    private var startRequested = false
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    func markStart() {
        lock.withLock { startRequested = true }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete,
              let pixels = sampleBuffer.imageBuffer,
              lock.withLock({ startRequested })
        else { return }
        let time = sampleBuffer.presentationTimeStamp
        if start == nil { start = time }
        let milliseconds = Int(((time - (start ?? time)).seconds * 1000).rounded())
        let image = CIImage(cvPixelBuffer: pixels)
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: directory.appending(path: String(format: "%05d.png", milliseconds)))
    }
}

/// A window AppKit treats as key although the test process never becomes the active app, so
/// controls draw their focused and active states and take clicks without stealing focus.
final class AlwaysKeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}
