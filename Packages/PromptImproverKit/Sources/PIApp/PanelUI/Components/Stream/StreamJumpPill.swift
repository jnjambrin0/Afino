import AppKit
import PIDesign
import SwiftUI

/// "↓ Jump to latest": a small glass capsule at the bottom of the well while the person has
/// scrolled away from text that keeps arriving. 24 pt tall (`EmberDesign.Control.smallHeight`),
/// with a 28 pt hit target (`EmberDesign.Control.minimumHitTarget`).
struct StreamJumpPill: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.down")
                .font(EmberDesign.Typography.badge)
                .foregroundStyle(.primary)
                .padding(.horizontal, EmberDesign.Spacing.m)
                .frame(height: EmberDesign.Control.smallHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.vertical, (EmberDesign.Control.minimumHitTarget - EmberDesign.Control.smallHeight) / 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// The capsule's label, from `Localizable.xcstrings`.
    static var localizedTitle: String {
        String(localized: "stream.jumpToLatest", defaultValue: "Jump to latest", bundle: .module, comment: "Capsule in the result: scrolls back to the newest text")
    }
}

/// Hosts the pill and fades it in and out (opacity only, so it is the same under Reduce Motion).
final class StreamJumpPillHost: NSView {
    private let hosting: NSHostingView<StreamJumpPill>

    /// Whether the pill is showing or fading in.
    private(set) var isShown = false

    init(title: String, action: @escaping () -> Void) {
        hosting = NSHostingView(rootView: StreamJumpPill(title: title, action: action))
        super.init(frame: .zero)
        hosting.sizingOptions = [.intrinsicContentSize]
        addSubview(hosting)
        alphaValue = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var fittingSize: NSSize {
        hosting.fittingSize
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    /// Fades the pill in or out; it stays hidden (and out of hit testing) once faded out.
    func setShown(_ shown: Bool, animated: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            isHidden = false
        }
        guard animated else {
            alphaValue = shown ? 1 : 0
            hideIfDismissed()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.contentCrossfadeDuration
            animator().alphaValue = shown ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.hideIfDismissed() }
        }
    }

    private func hideIfDismissed() {
        if !isShown {
            isHidden = true
        }
    }
}
