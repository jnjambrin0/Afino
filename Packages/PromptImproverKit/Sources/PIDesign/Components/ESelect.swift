import SwiftUI

/// A menu-button select: the current value and a chevron; clicking it opens
/// an `EMenuCard` with the current value checked. ↑/↓ move the highlight,
/// ↩/Space choose, Esc or a click outside closes. VoiceOver and UI tests see
/// a native pop-up picker.
///
/// The card floats in the window's `emberFloatingLayer()`; apply it once at
/// the root of the window content.
///
/// ```swift
/// ESelect("Preset", options: Preset.allCases, selection: $preset) { $0.title }
/// ```
public struct ESelect<Value: Hashable>: View {
    public let label: String
    public let options: [Value]
    @Binding public var selection: Value
    public let title: (Value) -> String
    public var monogram: ((Value) -> EMonogram?)?
    public var preferAbove: Bool
    public var minWidth: CGFloat?

    @State private var isOpen = false
    @State private var buttonWidth: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - label: What VoiceOver calls the control ("Preset").
    ///   - minWidth: The button's minimum width (it otherwise hugs its value).
    ///   - preferAbove: Opens the card above the button when there is room there.
    ///   - monogram: An optional tile for each option (targets, providers).
    public init(
        _ label: String,
        options: [Value],
        selection: Binding<Value>,
        minWidth: CGFloat? = nil,
        preferAbove: Bool = false,
        monogram: ((Value) -> EMonogram?)? = nil,
        title: @escaping (Value) -> String
    ) {
        self.label = label
        self.options = options
        self._selection = selection
        self.minWidth = minWidth
        self.preferAbove = preferAbove
        self.monogram = monogram
        self.title = title
    }

    public var body: some View {
        Button(action: toggle) {
            HStack(spacing: EmberDesign.Spacing.s) {
                if let tile = monogram?(selection) {
                    EMonogramTile(tile)
                }
                Text(verbatim: title(selection))
                    .font(EmberDesign.Typography.selectValue)
                Spacer(minLength: EmberDesign.Spacing.xxs)
                Image(systemName: EmberDesign.Control.selectChevron)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: minWidth, alignment: .leading)
        }
        .buttonStyle(.ember(.secondary))
        .fixedSize(horizontal: true, vertical: false)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { buttonWidth = $0 }
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(options, id: \.self) { Text(verbatim: title($0)).tag($0) }
            } label: {
                Text(verbatim: label)
            }
            .pickerStyle(.menu)
            // The row shows the title; the pop-up keeps it as its name only, over the
            // button's whole frame.
            .labelsHidden()
            .disabled(!isEnabled)
        }
        .emberFloatingCard(isPresented: $isOpen, preferAbove: preferAbove) {
            ESelectMenu(
                items: items,
                width: max(buttonWidth, EmberDesign.Card.selectMenuMinWidth),
                initialHighlight: selectedIndex.map(String.init),
                onChoose: choose,
                onClose: close
            )
        }
    }

    private var selectedIndex: Int? {
        options.firstIndex(of: selection)
    }

    private var items: [EMenuItem] {
        options.enumerated().map { index, option in
            EMenuItem(
                id: String(index),
                title: title(option),
                monogram: monogram?(option),
                isChecked: option == selection
            )
        }
    }

    private func toggle() {
        withAnimation(isOpen ? EmberDesign.Motion.menuOut : EmberDesign.Motion.menuIn) {
            isOpen.toggle()
        }
    }

    private func close() {
        withAnimation(EmberDesign.Motion.menuOut) { isOpen = false }
    }

    private func choose(_ id: String) {
        if let index = Int(id), options.indices.contains(index) {
            selection = options[index]
        }
        close()
    }
}

/// The select's card with its own keyboard handling.
private struct ESelectMenu: View {
    let items: [EMenuItem]
    let width: CGFloat
    let initialHighlight: String?
    let onChoose: (String) -> Void
    let onClose: () -> Void

    @State private var highlightedID: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        EMenuCard(
            items: items,
            highlightedID: highlightedID,
            width: width,
            onHover: { highlightedID = $0 },
            onSelect: onChoose
        )
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            highlightedID = initialHighlight ?? items.first(where: \.isEnabled)?.id
            isFocused = true
        }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.return) { chooseHighlighted() }
        .onKeyPress(.space) { chooseHighlighted() }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private var selectable: [EMenuItem] {
        items.filter { $0.isEnabled && !$0.isHeader }
    }

    private func move(by step: Int) -> KeyPress.Result {
        let rows = selectable
        guard !rows.isEmpty else { return .handled }
        let current = rows.firstIndex { $0.id == highlightedID }
        let next: Int
        if let current {
            next = (current + step + rows.count) % rows.count
        } else {
            next = step > 0 ? 0 : rows.count - 1
        }
        highlightedID = rows[next].id
        return .handled
    }

    private func chooseHighlighted() -> KeyPress.Result {
        guard let highlightedID else { return .ignored }
        onChoose(highlightedID)
        return .handled
    }
}
