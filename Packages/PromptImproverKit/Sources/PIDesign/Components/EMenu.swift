import SwiftUI

/// One row of an `EMenuCard`.
public struct EMenuItem: Identifiable, Equatable, Sendable {
    /// What `EMenuCard` reports on hover and selection.
    public let id: String
    public var title: String
    /// A leading SF Symbol.
    public var symbol: String?
    /// A leading monogram tile (takes precedence over `symbol`).
    public var monogram: EMonogram?
    /// The shortcut, shown as trailing caps.
    public var shortcut: KeyChord?
    /// Shortcut caps when the shortcut isn't a `KeyChord` (a recorded one).
    public var caps: [String]
    /// Disabled rows are dimmed and ignore hover and clicks.
    public var isEnabled: Bool
    /// The current choice: a trailing checkmark and the `isSelected` trait.
    public var isChecked: Bool
    /// Why the row is disabled, shown under its title.
    public var hint: String?
    /// Red only while highlighted.
    public var isDestructive: Bool
    /// Rows with different sections are separated by a hairline.
    public var section: Int
    /// A section title ("Engine"); never selectable.
    public var isHeader: Bool

    public init(
        id: String,
        title: String,
        symbol: String? = nil,
        monogram: EMonogram? = nil,
        shortcut: KeyChord? = nil,
        caps: [String] = [],
        isEnabled: Bool = true,
        isChecked: Bool = false,
        hint: String? = nil,
        isDestructive: Bool = false,
        section: Int = 0,
        isHeader: Bool = false
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.monogram = monogram
        self.shortcut = shortcut
        self.caps = caps
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.hint = hint
        self.isDestructive = isDestructive
        self.section = section
        self.isHeader = isHeader
    }

    /// A section title row.
    public static func header(id: String, title: String, section: Int) -> EMenuItem {
        EMenuItem(id: id, title: title, isEnabled: false, section: section, isHeader: true)
    }
}

/// The Ember menu card: a glass card with an optional filter field, grouped
/// rows, shortcuts as caps, an optional checkmark and the native selection
/// pair on the highlighted row. Keyboard routing (↑/↓/↩/Esc) is the owner's
/// job (`ESelect` does it for itself); rows also respond to hover and click.
/// Never animate the highlight.
public struct EMenuCard: View {
    public let items: [EMenuItem]
    /// The row drawn with the selection pair.
    public let highlightedID: String?
    /// The filter field's text; no field without it. Filtering `items` is the owner's job.
    public var filter: Binding<String>?
    public var filterPlaceholder: String
    /// Shown instead of the rows when `items` is empty.
    public var emptyMessage: String
    public var width: CGFloat
    public var filterAccessibilityIdentifier: String?
    /// Called with a row's `id` when the pointer enters it.
    public let onHover: (String) -> Void
    /// Called with a row's `id` when it is clicked.
    public let onSelect: (String) -> Void

    @FocusState private var filterFocused: Bool

    public init(
        items: [EMenuItem],
        highlightedID: String?,
        filter: Binding<String>? = nil,
        filterPlaceholder: String = "",
        emptyMessage: String = "",
        width: CGFloat = EmberDesign.Card.menuWidth,
        filterAccessibilityIdentifier: String? = nil,
        onHover: @escaping (String) -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        self.items = items
        self.highlightedID = highlightedID
        self.filter = filter
        self.filterPlaceholder = filterPlaceholder
        self.emptyMessage = emptyMessage
        self.width = width
        self.filterAccessibilityIdentifier = filterAccessibilityIdentifier
        self.onHover = onHover
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let filter {
                HStack(spacing: EmberDesign.Spacing.s) {
                    Image(systemName: "magnifyingglass")
                        .font(EmberDesign.Typography.message)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    TextField(
                        text: filter,
                        prompt: Text(verbatim: filterPlaceholder).foregroundStyle(EmberDesign.Status.placeholder)
                    ) {
                        Text(verbatim: filterPlaceholder)
                    }
                    .textFieldStyle(.plain)
                    .font(EmberDesign.Typography.menuItem)
                    .focused($filterFocused)
                    .emberAccessibilityIdentifier(filterAccessibilityIdentifier)
                }
                .padding(.horizontal, EmberDesign.Spacing.s + EmberDesign.Card.menuPadding)
                .frame(height: EmberDesign.Card.menuRowHeight + EmberDesign.Spacing.xs)

                separator
            }

            if items.isEmpty {
                Text(verbatim: emptyMessage)
                    .font(EmberDesign.Typography.message)
                    .foregroundStyle(.secondary)
                    .padding(EmberDesign.Spacing.m)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0, items[index - 1].section != item.section {
                            separator
                                .padding(.vertical, EmberDesign.Card.menuSectionSpacing)
                        }
                        if item.isHeader {
                            Text(verbatim: item.title)
                                .font(EmberDesign.Typography.menuSection)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, EmberDesign.Spacing.s)
                                .padding(.top, EmberDesign.Spacing.xxs)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            EMenuRow(item: item, isHighlighted: item.id == highlightedID, onHover: onHover, onSelect: onSelect)
                        }
                    }
                }
                .padding(EmberDesign.Card.menuPadding)
            }
        }
        .frame(width: width)
        .emberFloatingCardSurface(cornerRadius: EmberDesign.Radius.large)
        .onAppear { filterFocused = filter != nil }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: EmberDesign.Control.hairlineWidth)
            .padding(.horizontal, EmberDesign.Spacing.s)
    }
}

private struct EMenuRow: View {
    let item: EMenuItem
    let isHighlighted: Bool
    let onHover: (String) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: EmberDesign.Spacing.s) {
                leadingGlyph
                    .frame(width: EmberDesign.Card.menuGlyphColumn)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: item.title)
                        .foregroundStyle(titleStyle)
                    if let hint = item.hint {
                        Text(verbatim: hint)
                            .font(EmberDesign.Typography.fieldHelp)
                            .foregroundStyle(isHighlighted ? AnyShapeStyle(EmberDesign.Selection.secondaryForeground) : AnyShapeStyle(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: EmberDesign.Spacing.m)
                if let shortcut = item.shortcut {
                    EKeyCapGroup(shortcut)
                } else if !item.caps.isEmpty {
                    EKeyCapGroup(caps: item.caps)
                }
                if item.isChecked {
                    Image(systemName: "checkmark")
                        .font(EmberDesign.Typography.messageGlyph)
                        .foregroundStyle(titleStyle)
                        .accessibilityHidden(true)
                }
            }
            .environment(\.emberKeyCapBackdrop, isHighlighted ? .selection : .plain)
            .font(EmberDesign.Typography.menuItem)
            .padding(.horizontal, EmberDesign.Spacing.s)
            .padding(.vertical, item.hint == nil ? 0 : EmberDesign.Spacing.xs)
            .frame(minHeight: EmberDesign.Card.menuRowHeight)
            .contentShape(Rectangle())
            .background(
                // Concentric with the card: its radius minus the card's padding.
                RoundedRectangle(cornerRadius: EmberDesign.Radius.menuRow, style: .continuous)
                    .fill(highlightFill)
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : EmberDesign.Control.disabledOpacity)
        .onHover { hovering in
            if hovering, item.isEnabled { onHover(item.id) }
        }
        .accessibilityLabel(Text(verbatim: item.hint.map { "\(item.title), \($0)" } ?? item.title))
        .accessibilityAddTraits(item.isChecked ? [.isSelected] : [])
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if let monogram = item.monogram {
            EMonogramTile(monogram)
                .foregroundStyle(titleStyle)
        } else if let symbol = item.symbol {
            Image(systemName: symbol)
                .foregroundStyle(symbolStyle)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    private var highlightFill: AnyShapeStyle {
        guard isHighlighted else { return AnyShapeStyle(.clear) }
        return item.isDestructive ? AnyShapeStyle(EmberDesign.Status.negative) : AnyShapeStyle(EmberDesign.Selection.background)
    }

    private var titleStyle: AnyShapeStyle {
        isHighlighted ? AnyShapeStyle(EmberDesign.Selection.foreground) : AnyShapeStyle(.primary)
    }

    private var symbolStyle: AnyShapeStyle {
        if isHighlighted {
            return AnyShapeStyle(EmberDesign.Selection.foreground)
        }
        return item.isDestructive ? AnyShapeStyle(EmberDesign.Status.negative) : AnyShapeStyle(.secondary)
    }
}
