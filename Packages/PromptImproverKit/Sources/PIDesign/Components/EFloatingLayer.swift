import AppKit
import SwiftUI

// Floating cards (menus, selects) drawn above everything in a window, so a
// card opened from a control deep inside a row or a card is never covered by
// later siblings or clipped by its container. Apply `emberFloatingLayer()`
// once at the root of a window's SwiftUI content (the panel root, the
// Settings root); controls attach cards with `emberFloatingCard`.

public extension View {
    /// Hosts the floating cards attached anywhere below this view. A click
    /// outside an open card (or Esc inside it, see `ESelect`) dismisses it.
    func emberFloatingLayer() -> some View {
        modifier(EFloatingLayer())
    }

    /// Floats `card` next to this view while `isPresented`: leading edges
    /// aligned, below it, or above when there is no room below. Drawn by the
    /// nearest `emberFloatingLayer()`; without one the card is drawn as a
    /// plain overlay under the view (it may then be covered by later
    /// siblings). Animate `isPresented` with `Motion.menuIn` / `Motion.menuOut`.
    func emberFloatingCard<Card: View>(
        isPresented: Binding<Bool>,
        preferAbove: Bool = false,
        @ViewBuilder card: @escaping () -> Card
    ) -> some View {
        modifier(EFloatingCardSource(isPresented: isPresented, preferAbove: preferAbove, card: card))
    }
}

extension EnvironmentValues {
    /// Whether an `emberFloatingLayer()` above will draw floating cards.
    @Entry var emberFloatingLayerIsPresent = false
}

/// One open card, passed up the view tree to the floating layer as a preference.
struct EFloatingRequest: Identifiable {
    let id: UUID
    let anchor: Anchor<CGRect>
    let preferAbove: Bool
    let content: AnyView
    let dismiss: () -> Void
}

struct EFloatingRequestsKey: PreferenceKey {
    static var defaultValue: [EFloatingRequest] { [] }

    static func reduce(value: inout [EFloatingRequest], nextValue: () -> [EFloatingRequest]) {
        value.append(contentsOf: nextValue())
    }
}

private struct EFloatingLayer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each open card's frame in the layer, so a click can be told inside from outside.
    @State private var cardFrames: [UUID: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .environment(\.emberFloatingLayerIsPresent, true)
            .overlayPreferenceValue(EFloatingRequestsKey.self) { requests in
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        if let topmost = requests.last {
                            // Like a native menu: a click anywhere outside the card closes it and
                            // does nothing else (it is not passed to what lies under it).
                            EOutsideClickMonitor(
                                cardFrames: requests.compactMap { cardFrames[$0.id] },
                                onOutsideClick: topmost.dismiss
                            )
                            .accessibilityHidden(true)
                        }
                        ForEach(requests) { request in
                            EAttachedPlacementLayout(anchor: proxy[request.anchor], preferAbove: request.preferAbove) {
                                request.content
                                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(EFloatingLayerSpace.name)) }) {
                                        cardFrames[request.id] = $0
                                    }
                            }
                            .transition(EmberDesign.Motion.menuTransition(
                                anchor: request.preferAbove ? .bottomLeading : .topLeading,
                                reduceMotion: reduceMotion
                            ))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .coordinateSpace(.named(EFloatingLayerSpace.name))
                    .onChange(of: requests.map(\.id)) { _, open in
                        cardFrames = cardFrames.filter { open.contains($0.key) }
                    }
                }
            }
    }
}

nonisolated enum EFloatingLayerSpace {
    static let name = "emberFloatingLayer"
}

/// Watches mouse-downs in its window while a floating card is open. A click outside every card
/// (in the window, or in another window of the app) calls `onOutsideClick`; inside the window it
/// is swallowed, so the click that closes a menu never also presses the control under it. The
/// view itself fills the layer and takes no events.
struct EOutsideClickMonitor: NSViewRepresentable {
    /// The open cards, in the layer's coordinates (top-left origin).
    let cardFrames: [CGRect]
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.cardFrames = cardFrames
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.cardFrames = cardFrames
        view.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stop()
    }

    final class MonitorView: NSView {
        var cardFrames: [CGRect] = []
        var onOutsideClick: () -> Void = {}
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                // Local monitors run on the main thread, inside the event dispatch.
                let location = event.locationInWindow
                let windowNumber = event.windowNumber
                let swallow = MainActor.assumeIsolated {
                    self?.shouldSwallow(location: location, windowNumber: windowNumber) ?? false
                }
                return swallow ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Closes the card on a click outside it; true when the click must not reach anything else.
        private func shouldSwallow(location: NSPoint, windowNumber: Int) -> Bool {
            guard let window else { return false }
            guard windowNumber == window.windowNumber else {
                // A click in another window of the app (a panel, an alert) closes the card too.
                onOutsideClick()
                return false
            }
            let point = convert(location, from: nil)
            guard !EFloatingPlacement.contains(point, in: cardFrames) else { return false }
            onOutsideClick()
            return true
        }

        deinit {
            MainActor.assumeIsolated { stop() }
        }
    }
}

private struct EFloatingCardSource<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let preferAbove: Bool
    let card: () -> Card

    @Environment(\.emberFloatingLayerIsPresent) private var hasLayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var id = UUID()
    /// The view's height, for the fallback without a layer.
    @State private var anchorHeight: CGFloat = 0

    func body(content: Content) -> some View {
        if hasLayer {
            // Built here, not in the transform, so the closure captures no
            // generic metatype.
            let cardView = isPresented ? AnyView(card()) : nil
            let requestID = id
            let above = preferAbove
            let binding = $isPresented
            content
                .anchorPreference(key: EFloatingRequestsKey.self, value: .bounds) { anchor in
                    guard let cardView else { return [] }
                    return [EFloatingRequest(
                        id: requestID,
                        anchor: anchor,
                        preferAbove: above,
                        content: cardView,
                        dismiss: {
                            withAnimation(EmberDesign.Motion.menuOut) { binding.wrappedValue = false }
                        }
                    )]
                }
        } else {
            // Below: the card's top edge starts at the view's top and moves
            // down by the view's height plus the gap. Above: its bottom edge
            // starts at the view's bottom and moves up by the same distance.
            let distance = anchorHeight + EmberDesign.Card.anchorGap
            content
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { anchorHeight = $0 }
                .overlay(alignment: preferAbove ? .bottomLeading : .topLeading) {
                    if isPresented {
                        card()
                            .fixedSize()
                            .offset(y: preferAbove ? -distance : distance)
                            .transition(EmberDesign.Motion.menuTransition(
                                anchor: preferAbove ? .bottomLeading : .topLeading,
                                reduceMotion: reduceMotion
                            ))
                    }
                }
                .zIndex(isPresented ? 1 : 0)
        }
    }
}

/// Fills its container and places each child, at its ideal size, attached to
/// `anchor` (`EFloatingPlacement.origin(for:attachedTo:in:)`).
struct EAttachedPlacementLayout: Layout {
    let anchor: CGRect
    let preferAbove: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let placement = EFloatingPlacement.origin(
                for: size,
                attachedTo: anchor,
                in: bounds.size,
                preferAbove: preferAbove
            )
            subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(size)
            )
        }
    }
}

/// Positions a floating card inside its container (top-left origin), kept
/// `Card.edgeMargin` inside the edges.
nonisolated enum EFloatingPlacement {
    /// A card attached to a control (a select button): leading edges aligned,
    /// `gap` below the control, or above it when there is no room below (or
    /// `preferAbove` and there is room above). Never covers the control when
    /// either side has room.
    static func origin(
        for cardSize: CGSize,
        attachedTo anchor: CGRect,
        in container: CGSize,
        gap: CGFloat = EmberDesign.Card.anchorGap,
        preferAbove: Bool = false
    ) -> (origin: CGPoint, isAbove: Bool) {
        let margin = EmberDesign.Card.edgeMargin
        let below = anchor.maxY + gap
        let above = anchor.minY - gap - cardSize.height
        let fitsBelow = below + cardSize.height <= container.height - margin
        let fitsAbove = above >= margin
        let isAbove = preferAbove ? (fitsAbove || !fitsBelow) : (!fitsBelow && fitsAbove)

        let x = clamp(anchor.minX, cardLength: cardSize.width, containerLength: container.width)
        let y = clamp(isAbove ? above : below, cardLength: cardSize.height, containerLength: container.height)
        return (CGPoint(x: x, y: y), isAbove)
    }

    /// Whether `point` falls inside any of the open cards (a click there is the card's own).
    static func contains(_ point: CGPoint, in cards: [CGRect]) -> Bool {
        cards.contains { $0.contains(point) }
    }

    private static func clamp(_ value: CGFloat, cardLength: CGFloat, containerLength: CGFloat) -> CGFloat {
        let margin = EmberDesign.Card.edgeMargin
        return min(max(value, margin), max(containerLength - cardLength - margin, margin))
    }
}
