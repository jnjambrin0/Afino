import PIDesign
import SwiftUI

/// The ⌘K menu or the target menu, drawn in the floating card window. The panel's key map moves
/// the highlight and runs the highlighted row; hover and click work directly. The highlight is
/// never animated.
struct PanelMenuCardView: View {
    let controller: PanelController
    let kind: PanelMenuKind

    /// The target menu is narrower than ⌘K: monogram, name, caps and a check.
    static var targetMenuWidth: CGFloat {
        EmberDesign.Card.selectMenuMinWidth + EmberDesign.Spacing.xl
    }

    var body: some View {
        let entries = controller.menuEntries(kind)
        EMenuCard(
            items: entries.map(\.item),
            highlightedID: controller.model.highlightedMenuItemID,
            width: kind == .actions ? EmberDesign.Card.menuWidth : Self.targetMenuWidth,
            onHover: { controller.model.highlightedMenuItemID = $0 },
            onSelect: { controller.executeMenuItem($0) }
        )
        .fixedSize()
        .accessibilityLabel(Text(verbatim: kind == .actions ? PanelStrings.actions : PanelStrings.targetMenuTitle))
        .accessibilityIdentifier(kind == .actions ? PanelAccessibilityID.actionsMenu : PanelAccessibilityID.targetMenu)
    }
}
