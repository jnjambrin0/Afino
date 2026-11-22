import AppKit
import PIDesign
import SwiftUI

/// What the panel shrinks into after Copy & Close: the accent check (the caret's last form) with
/// one bounce, and "Copied". Never interactive.
struct CopiedPillView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Image(systemName: "checkmark")
                .font(Self.checkmarkFont)
                .foregroundStyle(EmberDesign.Brand.accentMark)
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
            Text(verbatim: PanelStrings.copied)
                .font(EmberDesign.Typography.confirmation)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { bounce += 1 } }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(PanelAccessibilityID.copiedPill)
    }

    /// A bold check a step larger than the label.
    static let checkmarkFont: Font = .title2.weight(.bold)

    /// The pill's size: the label plus the confirmation padding, never under the minimum width.
    static func pillSize() -> CGSize {
        let labelFont = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)
        let textWidth = (PanelStrings.copied as NSString).size(withAttributes: [.font: labelFont]).width
        let checkWidth = NSFont.preferredFont(forTextStyle: .title2).pointSize * EmberDesign.Confirmation.symbolWidthFactor
        let width = textWidth + checkWidth + EmberDesign.Spacing.s + EmberDesign.Confirmation.horizontalPadding * 2
        return CGSize(
            width: max(ceil(width), EmberDesign.Confirmation.pillMinWidth),
            height: EmberDesign.Confirmation.pillHeight)
    }
}
