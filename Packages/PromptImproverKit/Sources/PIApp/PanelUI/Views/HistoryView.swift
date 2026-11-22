import PICore
import PIDesign
import SwiftUI

/// ⌘Y: the panel's content becomes a filterable list of past improvements. ↑/↓ (wrapping) move
/// the selection, Return opens one as a result (and copies it), ⌘⌫ deletes with a 5 s undo, Esc
/// goes back.
struct HistoryView: View {
    let controller: PanelController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let history = controller.model.history
        let visible = history.visible
        VStack(spacing: 0) {
            filterRow
            list(visible: visible, history: history)
                .frame(maxHeight: .infinity)
            footer(count: history.entries.count)
                .frame(height: EmberDesign.Panel.footerHeight)
        }
        .overlay(alignment: .bottom) {
            if history.deleted != nil {
                EToast(
                    PanelStrings.historyDeleted,
                    symbol: "trash",
                    actionTitle: PanelStrings.undo,
                    actionChord: PanelKeyMap.chord(for: .undoDelete, in: .history)
                ) {
                    controller.undoHistoryDelete()
                }
                .padding(.bottom, EmberDesign.Panel.footerHeight + EmberDesign.Spacing.s)
                .transition(EmberDesign.Motion.toastTransition(reduceMotion: reduceMotion))
                .accessibilityIdentifier(PanelAccessibilityID.historyToast)
            }
        }
        .animation(history.deleted == nil ? EmberDesign.Motion.toastOut : EmberDesign.Motion.toastIn, value: history.deleted?.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PanelAccessibilityID.history)
    }

    private var filterRow: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(EmberDesign.Typography.input)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            HostedView(view: controller.filterField)
                .frame(maxWidth: .infinity)
                .frame(height: EmberDesign.Panel.inputLineHeight + EmberDesign.Spacing.xs)
                .accessibilityLabel(Text(verbatim: PanelStrings.historyFilterPlaceholder))
        }
        .padding(.horizontal, PanelLayout.textLeadingInset)
        .frame(height: PanelLayout.historyFilterHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: EmberDesign.Control.hairlineWidth)
                .padding(.horizontal, EmberDesign.Panel.contentInset)
        }
    }

    @ViewBuilder
    private func list(visible: [HistoryEntry], history: PanelHistoryState) -> some View {
        if history.isLoaded, visible.isEmpty {
            Text(verbatim: history.entries.isEmpty ? PanelStrings.historyEmpty : PanelStrings.historyNoMatches)
                .font(EmberDesign.Typography.emptyBody)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            HistoryRowView(
                                content: HistoryRowFormatter.row(for: entry, library: controller.library, now: .now),
                                isSelected: entry.id == history.selectedID
                            )
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { controller.openHistoryEntry(entry) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(entry.id == history.selectedID ? .isSelected : [])
                            .accessibilityIdentifier(PanelAccessibilityID.historyRow(index))
                        }
                    }
                    .padding(.vertical, PanelLayout.historyListPadding)
                    .padding(.horizontal, EmberDesign.Panel.contentInset)
                }
                .scrollIndicators(.automatic)
                .onChange(of: history.selectedID) { _, id in
                    // Keeping the selection in view is scrolling, which never animates.
                    if let id { proxy.scrollTo(id) }
                }
            }
            .accessibilityIdentifier(PanelAccessibilityID.historyList)
        }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Text(verbatim: PanelStrings.historyCount(count))
                .font(EmberDesign.Typography.hint)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: EmberDesign.Spacing.s)
            HStack(spacing: EmberDesign.Spacing.xxs) {
                ForEach(PanelPresentation.historyHints, id: \.self) { hint in
                    PanelHintButton(hint: hint) { controller.perform(hint.command) }
                }
            }
        }
        .padding(.leading, PanelLayout.textLeadingInset)
        .padding(.trailing, EmberDesign.Panel.contentInset)
    }
}

/// One past improvement: who it was for, the draft's first line, a preview of the result and
/// when. The selection uses the system's selection colours.
struct HistoryRowView: View {
    let content: HistoryRowContent
    let isSelected: Bool

    var body: some View {
        HStack(spacing: EmberDesign.Spacing.m) {
            EMonogramTile(content.monogram)
                .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.foreground) : AnyShapeStyle(.primary))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: content.title)
                    .font(EmberDesign.Typography.menuItem)
                    .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.foreground) : AnyShapeStyle(.primary))
                Text(verbatim: content.preview)
                    .font(EmberDesign.Typography.message)
                    .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.secondaryForeground) : AnyShapeStyle(.secondary))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: EmberDesign.Spacing.s)
            Text(verbatim: content.time ?? PanelStrings.historyNow)
                .font(EmberDesign.Typography.hint)
                .monospacedDigit()
                .foregroundStyle(isSelected ? AnyShapeStyle(EmberDesign.Selection.secondaryForeground) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, EmberDesign.Spacing.m)
        .frame(height: PanelLayout.historyRowHeight)
        .background(
            RoundedRectangle(cornerRadius: EmberDesign.Radius.medium, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(EmberDesign.Selection.background) : AnyShapeStyle(.clear))
        )
        .accessibilityElement(children: .combine)
    }
}
