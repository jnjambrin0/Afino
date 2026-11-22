import PIDesign
import SwiftUI

/// The Settings window content: a floating glass sidebar and the selected pane. ⌘1…⌘5 select
/// panes. Dialogs and floating cards (selects) are drawn over the whole window.
struct SettingsRootView: View {
    let model: SettingsWindowModel
    let context: SettingsContext

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model)
                .frame(width: EmberDesign.Settings.sidebarWidth)
                .padding(EmberDesign.Settings.sidebarInset)

            SettingsPaneView(pane: model.selectedPane, model: model, context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.selectedPane)
        }
        .frame(
            minWidth: EmberDesign.Settings.windowSize.width,
            maxWidth: .infinity,
            minHeight: EmberDesign.Settings.windowSize.height,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .emberFloatingLayer()
        .emberDialog(isPresented: model.dialog != nil) {
            dialog(for: model.dialog)
        }
        // Last, so the dialog's scrim also covers the title bar.
        .ignoresSafeArea()
    }

    private func dialog(for dialog: SettingsDialog?) -> EDialog {
        guard let dialog else { return EDialog("", actions: []) }
        return EDialog(
            dialog.title,
            message: dialog.message,
            symbol: dialog.symbol,
            actions: dialog.actions.map { action in
                EDialogAction(
                    action.title,
                    kind: kind(for: action.role),
                    // Return confirms a harmless action; a destructive one takes a click.
                    isDefault: action.role == .confirm,
                    isCancel: action.role == .cancel
                ) { [model] in
                    model.dialog = nil
                    action.action()
                }
            }
        )
    }

    private func kind(for role: SettingsDialog.Action.Role) -> EButtonStyle.Kind {
        switch role {
        // Bordered, like an alert's Cancel: a bare word next to a filled button reads as disabled.
        case .cancel: .secondary
        case .confirm: .primary
        case .destructive: .destructive
        }
    }
}

/// One row per pane on a glass panel inset from the window's edges, below the traffic lights.
private struct SettingsSidebar: View {
    let model: SettingsWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
            Color.clear.frame(height: EmberDesign.Settings.titleBarClearance)
            ForEach(Array(SettingsPane.allCases.enumerated()), id: \.element) { index, pane in
                SettingsSidebarRow(pane: pane, isSelected: model.selectedPane == pane) {
                    model.selectedPane = pane
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, EmberDesign.Spacing.s)
        .padding(.bottom, EmberDesign.Spacing.s)
        .frame(maxHeight: .infinity, alignment: .top)
        // Concentric with the window's corners, whatever radius this macOS gives them (the
        // sidebar is inset by `sidebarInset` on three sides).
        .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: .fixed(EmberDesign.Radius.small)), isUniform: true))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: SettingsStrings.text("settings.sidebar.accessibility")))
    }
}

/// A pane's symbol and name: a filled symbol on the selection colours when selected, a quiet
/// fill on hover.
private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: EmberDesign.Spacing.s) {
                Image(systemName: pane.systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: EmberDesign.Card.menuGlyphColumn)
                    .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.foreground) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(verbatim: pane.title)
                    .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.foreground) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, EmberDesign.Spacing.s)
            .frame(height: EmberDesign.Settings.sidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: EmberDesign.Radius.control, style: .continuous)
                    .fill(fill)
            )
            .contentShape(.interaction, Rectangle())
            // The keyboard focus ring follows the row's rounded selection shape.
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: EmberDesign.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var fill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(EmberDesign.Selection.background) }
        return isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear)
    }
}

/// The selected pane's content.
private struct SettingsPaneView: View {
    let pane: SettingsPane
    let model: SettingsWindowModel
    let context: SettingsContext

    var body: some View {
        switch pane {
        case .general:
            GeneralPane(context: context)
        case .engine:
            EnginePane(context: context, model: model)
        case .instructions:
            InstructionsPane(settings: context.settings)
        case .shortcuts:
            ShortcutsPane(groups: model.shortcutReference, shortcut: context.shortcut) {
                model.selectedPane = .general
            }
        case .about:
            AboutPane(context: context, model: model)
        }
    }
}
