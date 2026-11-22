import AppKit
import PIDesign
import SwiftUI

/// Where a floating card goes on screen, next to the control it belongs to. Pure, so the
/// flipping rules are testable without windows. Screen coordinates (y grows upward).
nonisolated enum PanelCardPlacement {
    enum Edge: Sendable {
        /// The card's leading edge lines up with the anchor's (the target chip).
        case leading
        /// The card's trailing edge lines up with the anchor's (the ⌘K hint).
        case trailing
    }

    /// The card's frame: `gap` above the anchor when `preferAbove` and there is room, else below
    /// it, else above it anyway; kept `EmberDesign.Card.edgeMargin` inside the visible frame.
    static func frame(
        for size: CGSize,
        anchor: CGRect,
        visibleFrame: CGRect,
        edge: Edge,
        preferAbove: Bool,
        gap: CGFloat = EmberDesign.Card.anchorGap
    ) -> CGRect {
        let margin = EmberDesign.Card.edgeMargin
        let aboveY = anchor.maxY + gap
        let belowY = anchor.minY - gap - size.height
        let fitsAbove = aboveY + size.height <= visibleFrame.maxY - margin
        let fitsBelow = belowY >= visibleFrame.minY + margin
        let goesAbove = preferAbove ? (fitsAbove || !fitsBelow) : (!fitsBelow && fitsAbove)
        var y = goesAbove ? aboveY : belowY
        y = min(max(y, visibleFrame.minY + margin), max(visibleFrame.maxY - margin - size.height, visibleFrame.minY + margin))

        var x = edge == .leading ? anchor.minX : anchor.maxX - size.width
        x = min(max(x, visibleFrame.minX + margin), max(visibleFrame.maxX - margin - size.width, visibleFrame.minX + margin))
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}

/// A floating card (the ⌘K menu, the target menu) in a window of its own, a child of the panel.
///
/// The panel is only as tall as its state (96 pt while composing), and a menu of a dozen rows does
/// not fit inside it. A child window lets the card hang over or beyond the panel the way a real
/// menu does, while the panel stays key: the panel's key map routes ↑/↓/↩/Esc to the card and
/// clicks reach the card directly (this window never becomes key).
final class PanelFloatingCardWindow: NSPanel {
    private let hostingView = CardHostingView(rootView: AnyView(EmptyView()))
    /// Bumped on every show, so a fade-out that finishes late never hides a newer card.
    private var generation = 0

    /// The card's size as SwiftUI lays it out.
    private var cardSize: CGSize {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.intrinsicContentSize
        return CGSize(width: ceil(max(size.width, 1)), height: ceil(max(size.height, 1)))
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // The card's own size decides the window's (`cardSize`); the window never resizes itself.
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `card` next to `anchor` (screen coordinates), as a child of `parent`.
    func show<Card: View>(
        _ card: Card,
        anchor: CGRect,
        edge: PanelCardPlacement.Edge,
        preferAbove: Bool,
        parent: NSWindow,
        reduceMotion: Bool
    ) {
        generation += 1
        hostingView.rootView = AnyView(card)
        let size = cardSize
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        let frame = PanelCardPlacement.frame(for: size, anchor: anchor, visibleFrame: visible, edge: edge, preferAbove: preferAbove)
        setFrame(frame, display: true)
        appearance = parent.effectiveAppearance
        if parent.childWindows?.contains(self) != true {
            parent.addChildWindow(self, ordered: .above)
        }
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.menuInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        invalidateShadow()
    }

    /// Resizes the window to the card's size after its rows changed, keeping the anchor side.
    func refit(anchor: CGRect, edge: PanelCardPlacement.Edge, preferAbove: Bool) {
        guard isVisible else { return }
        let size = cardSize
        guard size != frame.size, let visible = screen?.visibleFrame else { return }
        setFrame(
            PanelCardPlacement.frame(for: size, anchor: anchor, visibleFrame: visible, edge: edge, preferAbove: preferAbove),
            display: true)
        invalidateShadow()
    }

    /// Detaches the card from the panel and orders it out, after a short fade when `animated`.
    func hide(animated: Bool) {
        guard isVisible else { return }
        let hiding = generation
        let finish: @MainActor () -> Void = { [weak self] in
            // A card shown again while this one faded out owns the window now.
            guard let self, generation == hiding else { return }
            parent?.removeChildWindow(self)
            orderOut(nil)
            hostingView.rootView = AnyView(EmptyView())
            alphaValue = 1
        }
        guard animated else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.menuOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { finish() }
        }
    }
}

/// The card's content. The card window never becomes key, so a click on a row must act at once
/// instead of being taken as a click that only brings the window forward.
private final class CardHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
