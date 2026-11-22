import AppKit
import PIDesign

/// What placement needs to know about a display, so the maths can be tested without screens.
nonisolated struct PanelScreenSnapshot: Equatable, Sendable {
    let identifier: String
    let frame: CGRect
    let visibleFrame: CGRect

    @MainActor
    init(screen: NSScreen) {
        identifier = PanelPlacement.screenIdentifier(for: screen)
        frame = screen.frame
        visibleFrame = screen.visibleFrame
    }

    init(identifier: String, frame: CGRect, visibleFrame: CGRect) {
        self.identifier = identifier
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Where the panel goes on one display: its top edge, its horizontal position and how tall it
/// may grow. The panel is anchored by its top edge: every height keeps that edge where it is
/// and only the bottom moves.
nonisolated struct PanelAnchor: Equatable, Sendable {
    /// The top edge, in screen coordinates (y grows upward).
    let top: CGFloat
    let minX: CGFloat
    let width: CGFloat
    let maxHeight: CGFloat

    /// The panel's frame at `height`, clamped to `1...maxHeight`.
    func frame(height: CGFloat) -> CGRect {
        let clamped = min(max(height.rounded(), 1), maxHeight)
        return CGRect(x: minX, y: top - clamped, width: width, height: clamped)
    }
}

/// Spotlight-like placement: a fixed width, horizontally centred in the visible frame of the
/// screen under the pointer, the top edge 22 % of the visible height below its top, growing only
/// downward.
nonisolated enum PanelPlacement {
    /// A stable per-display key. Prefers the display UUID (stable across reconnects and
    /// arrangement changes, unlike `NSScreenNumber`, which the system may reassign), then the
    /// screen number, then the frame.
    @MainActor
    static func screenIdentifier(for screen: NSScreen) -> String {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let screenNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) as String? {
            return uuidString
        }

        if let screenNumber {
            return String(screenNumber.uint32Value)
        }

        let integralFrame = screen.frame.integral
        return "\(Int(integralFrame.origin.x))x\(Int(integralFrame.origin.y))x\(Int(integralFrame.size.width))x\(Int(integralFrame.size.height))"
    }

    /// The screen under the pointer; else the one the panel was last on; else the first. A
    /// pointer pushed against a screen's top or right edge, where `NSEvent.mouseLocation` lands
    /// just outside its frame, still counts as on that screen unless another screen has it.
    static func resolveTargetScreen(
        mouseLocation: CGPoint,
        currentScreenIdentifier: String?,
        screens: [PanelScreenSnapshot]
    ) -> PanelScreenSnapshot? {
        if let mouseScreen = screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? screens.first(where: { closedContains($0.frame, mouseLocation) }) {
            return mouseScreen
        }

        if let currentScreenIdentifier,
           let currentScreen = screens.first(where: { $0.identifier == currentScreenIdentifier }) {
            return currentScreen
        }

        return screens.first
    }

    /// The anchor on `screen`: the top edge `topOffsetFraction` of the visible height below its
    /// top, and room for `min(maxHeightCap, visible height − offset − bottomMargin)`. When that
    /// room would be under `minUsableHeight`, the panel moves up — to no less than
    /// `minimumTopOffset` from the top — so it keeps that much room where the screen allows.
    static func anchor(
        on screen: PanelScreenSnapshot,
        width: CGFloat = EmberDesign.Panel.width,
        topOffsetFraction: CGFloat = EmberDesign.Panel.topOffsetFraction
    ) -> PanelAnchor {
        let visible = screen.visibleFrame
        var topOffset = (visible.height * topOffsetFraction).rounded()
        if visible.height - topOffset - EmberDesign.Panel.bottomMargin < EmberDesign.Panel.minUsableHeight {
            topOffset = max(PanelLayout.minimumTopOffset, visible.height - EmberDesign.Panel.bottomMargin - EmberDesign.Panel.minUsableHeight)
        }
        let maxHeight = max(min(EmberDesign.Panel.maxHeightCap, visible.height - topOffset - EmberDesign.Panel.bottomMargin), 1)
        let panelWidth = min(width, visible.width)
        return PanelAnchor(
            top: visible.maxY - topOffset,
            minX: (visible.midX - panelWidth / 2).rounded(),
            width: panelWidth,
            maxHeight: maxHeight
        )
    }

    /// A closed rectangle: its maximum edges belong to it.
    private static func closedContains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
