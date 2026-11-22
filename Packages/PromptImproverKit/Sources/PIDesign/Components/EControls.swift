import SwiftUI

// Ember input controls: fields, chips and the switch. Each keeps the native
// control underneath (or as its accessibility representation) so focus, input
// methods, VoiceOver and UI tests still see a text field, a picker or a switch.

/// The outline of a field: a rounded rectangle for text, a capsule for a
/// field-like button (the shortcut recorder).
public enum EFieldShape: Sendable {
    case roundedRectangle
    case capsule
}

public extension View {
    /// The field chrome around a plain `TextField`/`TextEditor`: a quiet fill,
    /// a hairline, the system focus colour when focused and a red ring when
    /// invalid.
    func emberFieldChrome(
        isFocused: Bool,
        isInvalid: Bool = false,
        verticalPadding: CGFloat = 0,
        shape: EFieldShape = .roundedRectangle
    ) -> some View {
        modifier(EFieldChrome(isFocused: isFocused, isInvalid: isInvalid, verticalPadding: verticalPadding, shape: shape))
    }
}

private struct EFieldChrome: ViewModifier {
    let isFocused: Bool
    let isInvalid: Bool
    let verticalPadding: CGFloat
    let shape: EFieldShape

    @Environment(\.colorScheme) private var colorScheme

    private var outline: AnyShape {
        switch shape {
        case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: EmberDesign.Radius.field, style: .continuous))
        case .capsule: AnyShape(Capsule(style: .continuous))
        }
    }

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, EmberDesign.Control.fieldHorizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: EmberDesign.Control.fieldHeight)
            .background(outline.fill(.background.opacity(EmberDesign.Glass.fieldOpacity(for: colorScheme))))
            .overlay(outline.stroke(borderStyle, lineWidth: EmberDesign.Control.hairlineWidth).padding(EmberDesign.Control.hairlineWidth / 2))
            // The focus and invalid rings sit outside the hairline, like the system's, so the
            // text inside never moves when the field gains focus.
            .overlay {
                if let ring = ringStyle {
                    outline
                        .stroke(ring, lineWidth: ringWidth)
                        .padding(-ringWidth / 2)
                        .allowsHitTesting(false)
                }
            }
    }

    private var borderStyle: AnyShapeStyle {
        AnyShapeStyle(.separator)
    }

    private var ringStyle: AnyShapeStyle? {
        if isInvalid { return AnyShapeStyle(EmberDesign.Status.negative) }
        if isFocused { return AnyShapeStyle(EmberDesign.Status.focusRing) }
        return nil
    }

    private var ringWidth: CGFloat {
        isInvalid ? EmberDesign.Control.invalidRingWidth : EmberDesign.Control.focusRingWidth
    }
}

/// A single-line text field with its own focus state.
public struct EField: View {
    public let placeholder: String
    @Binding public var text: String
    public var accessibilityLabel: String?
    /// Draws the red ring instead of the focus ring.
    public var isInvalid: Bool
    public var font: Font
    /// Called when the user presses Return in the field.
    public var onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    /// - Parameter accessibilityLabel: What VoiceOver calls the field
    ///   (defaults to the placeholder).
    public init(
        _ placeholder: String,
        text: Binding<String>,
        accessibilityLabel: String? = nil,
        isInvalid: Bool = false,
        font: Font = .body,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        self._text = text
        self.accessibilityLabel = accessibilityLabel
        self.isInvalid = isInvalid
        self.font = font
        self.onSubmit = onSubmit
    }

    public var body: some View {
        TextField(
            text: $text,
            prompt: Text(verbatim: placeholder).foregroundStyle(EmberDesign.Status.placeholder)
        ) {
            Text(verbatim: accessibilityLabel ?? placeholder)
        }
        .font(font)
        .focused($isFocused)
        .onSubmit(onSubmit)
        .emberFieldChrome(isFocused: isFocused, isInvalid: isInvalid)
    }
}

/// Choices as chips that wrap; one is always selected. VoiceOver sees a group
/// named after the choice, with one button per chip ("System, selected") at the
/// chip's own frame. The selected chip uses the system selection pair (selection
/// follows the user's accent colour, never the brand accent); its fill slides to
/// a new choice and carries the selected label colour with it, so no label is
/// ever drawn in the wrong colour mid-move (a crossfade under Reduce Motion).
public struct EChoiceChips<Value: Hashable>: View {
    public let options: [Value]
    @Binding public var selection: Value
    /// The text of each option's chip.
    public let title: (Value) -> String
    /// What VoiceOver calls the group.
    public var label: String
    /// Draws a focus ring for a form that moves keyboard focus itself (with Tab and ←/→).
    public var isFocused: Bool
    /// Unavailable options are dimmed and ignore clicks, but keep their tooltip.
    public var isAvailable: (Value) -> Bool
    /// Why an option is unavailable (its tooltip).
    public var unavailableHelp: (Value) -> String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ label: String,
        options: [Value],
        selection: Binding<Value>,
        isFocused: Bool = false,
        title: @escaping (Value) -> String
    ) {
        self.init(label, options: options, selection: selection, isFocused: isFocused, isAvailable: { _ in true }, title: title)
    }

    public init(
        _ label: String,
        options: [Value],
        selection: Binding<Value>,
        isFocused: Bool = false,
        isAvailable: @escaping (Value) -> Bool,
        unavailableHelp: @escaping (Value) -> String? = { _ in nil },
        title: @escaping (Value) -> String
    ) {
        self.label = label
        self.options = options
        self._selection = selection
        self.isFocused = isFocused
        self.isAvailable = isAvailable
        self.unavailableHelp = unavailableHelp
        self.title = title
    }

    private var selectedIndex: Int? {
        options.firstIndex(of: selection)
    }

    public var body: some View {
        EFlowLayout(spacing: EmberDesign.Spacing.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let available = isAvailable(option)
                EChip(
                    index: index,
                    title: title(option),
                    isSelected: index == selectedIndex,
                    isAvailable: available,
                    drawsOwnSelection: reduceMotion
                ) {
                    choose(option)
                }
                .emberHelp(available ? nil : unavailableHelp(option))
                .emberAccessibilityHint(available ? nil : unavailableHelp(option))
            }
        }
        .overlayPreferenceValue(EChipBoundsKey.self) { bounds in
            if !reduceMotion {
                EChipSelectionOverlay(bounds: bounds, selectedIndex: selectedIndex, titles: options.map(title))
                    // Scoped to the fill: what the new choice changes elsewhere (rows that appear,
                    // a model id) updates at once instead of riding the slide.
                    .animation(EmberDesign.Motion.selection(reduceMotion: false), value: selectedIndex)
            }
        }
        .padding(EmberDesign.Spacing.xxs)
        .overlay {
            if isFocused {
                // Concentric with the chips it surrounds (their radius plus the padding).
                RoundedRectangle(cornerRadius: EmberDesign.Control.chipHeight / 2 + EmberDesign.Spacing.xxs, style: .continuous)
                    .strokeBorder(EmberDesign.Status.focusRing, lineWidth: EmberDesign.Control.focusRingWidth)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
    }

    private func choose(_ option: Value) {
        guard option != selection, isAvailable(option) else { return }
        selection = option
    }
}

public extension EChoiceChips where Value == String {
    /// Chips whose options are their own titles.
    init(_ label: String, options: [String], selection: Binding<String>, isFocused: Bool = false) {
        self.init(label, options: options, selection: selection, isFocused: isFocused) { $0 }
    }
}

/// Each chip's capsule, by index, for the sliding selection.
struct EChipBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A chip's title and optional symbol. `EChoiceChips` draws it twice: plain, and in the
/// selection colour inside the sliding fill.
struct EChipLabel: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: EmberDesign.Spacing.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
                .lineLimit(1)
        }
        .font(EmberDesign.Typography.buttonSmall)
        .padding(.horizontal, EmberDesign.Control.chipHorizontalPadding)
        .frame(minHeight: EmberDesign.Control.chipHeight)
    }
}

private struct EChip: View {
    let index: Int
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    /// Under Reduce Motion each chip crossfades its own selection fill.
    let drawsOwnSelection: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var isActive: Bool { isEnabled && isAvailable }

    var body: some View {
        Button(action: action) {
            EChipLabel(title: title)
                .foregroundStyle(.primary)
                .overlay {
                    if drawsOwnSelection {
                        EChipLabel(title: title)
                            .foregroundStyle(EmberDesign.Selection.foreground)
                            .background(Capsule(style: .continuous).fill(EmberDesign.Selection.background))
                            .opacity(isSelected ? 1 : 0)
                            .animation(EmberDesign.Motion.selection(reduceMotion: true), value: isSelected)
                    }
                }
        }
        .buttonStyle(EChipButtonStyle(isHovered: isHovered && !isSelected, isActive: isActive, index: index))
        .onHover { isHovered = isActive && $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The chip's capsule: quiet fill, a step darker under the pointer and while pressed.
private struct EChipButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isActive: Bool
    let index: Int

    func makeBody(configuration: Configuration) -> some View {
        EChipCapsule(
            label: configuration.label,
            isHovered: isHovered,
            isPressed: configuration.isPressed && isActive,
            isActive: isActive,
            index: index
        )
    }
}

private struct EChipCapsule<Label: View>: View {
    let label: Label
    let isHovered: Bool
    let isPressed: Bool
    let isActive: Bool
    let index: Int

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = Capsule(style: .continuous)
        label
            .background(shape.fill(EmberDesign.Materials.quietFill(isHovered: isHovered, isPressed: isPressed)))
            .overlay {
                // Like secondary buttons: an outline under Increase Contrast.
                if contrast == .increased {
                    shape.strokeBorder(.separator, lineWidth: EmberDesign.Control.hairlineWidth)
                }
            }
            .anchorPreference(key: EChipBoundsKey.self, value: .bounds) { [index: $0] }
            .contentShape(.focusEffect, shape)
            .frame(minWidth: EmberDesign.Control.minimumHitTarget, minHeight: EmberDesign.Control.minimumHitTarget)
            .contentShape(.interaction, Rectangle())
            .opacity(isActive ? 1 : EmberDesign.Control.disabledOpacity)
    }
}

/// The selected fill and, clipped to it, every chip's label in the selection colour: as the
/// fill slides it reveals the selected colour exactly where it is.
private struct EChipSelectionOverlay: View {
    let bounds: [Int: Anchor<CGRect>]
    let selectedIndex: Int?
    let titles: [String]

    var body: some View {
        GeometryReader { proxy in
            if let selectedIndex, let anchor = bounds[selectedIndex] {
                let pill = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(EmberDesign.Selection.background)
                        .frame(width: pill.width, height: pill.height)
                        .offset(x: pill.minX, y: pill.minY)
                    ZStack(alignment: .topLeading) {
                        ForEach(titles.indices, id: \.self) { index in
                            if let chip = bounds[index].map({ proxy[$0] }) {
                                EChipLabel(title: titles[index])
                                    .foregroundStyle(EmberDesign.Selection.foreground)
                                    .frame(width: chip.width, height: chip.height)
                                    .offset(x: chip.minX, y: chip.minY)
                            }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .mask(alignment: .topLeading) {
                        Capsule(style: .continuous)
                            .frame(width: pill.width, height: pill.height)
                            .offset(x: pill.minX, y: pill.minY)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An action chip (an example to add, a suggestion): a quiet capsule with an optional leading
/// symbol, the same metrics as `EChoiceChips`. Unavailable chips are dimmed and ignore clicks but
/// keep their tooltip.
public struct EActionChip: View {
    public let title: String
    public var symbol: String?
    public var isAvailable: Bool
    public let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    public init(_ title: String, symbol: String? = nil, isAvailable: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isAvailable = isAvailable
        self.action = action
    }

    private var isActive: Bool { isEnabled && isAvailable }

    public var body: some View {
        Button {
            if isActive { action() }
        } label: {
            EChipLabel(title: title, symbol: symbol)
                .foregroundStyle(.primary)
        }
        .buttonStyle(EChipButtonStyle(isHovered: isHovered, isActive: isActive, index: -1))
        .onHover { isHovered = isActive && $0 }
    }
}

extension View {
    /// A tooltip, only when there is something to say.
    @ViewBuilder
    func emberHelp(_ text: String?) -> some View {
        if let text {
            help(Text(verbatim: text))
        } else {
            self
        }
    }
}

/// Lays children out in rows, wrapping to the proposed width.
public struct EFlowLayout: Layout {
    /// The gap between neighbors and between rows.
    public var spacing: CGFloat

    public init(spacing: CGFloat = EmberDesign.Spacing.xs) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, proposedWidth > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

/// The Ember switch: a capsule track with a round knob. It is a real button underneath, so
/// Full Keyboard Access reaches it, Space toggles it and the focus ring follows the capsule; its
/// accessibility representation is a native switch, so VoiceOver and `app.switches[...]` keep
/// working. `.toggleStyle(.ember)`.
///
/// Motion: the knob slides on a damped spring while the accent tint fades in over the same
/// spring (a separate layer, so the colour really crossfades instead of snapping). Pressing
/// stretches the knob toward the other end, like the system switch. Under Reduce Motion the knob
/// fades across instead of travelling.
public struct ESwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ESwitchBody(configuration: configuration)
    }
}

public extension ToggleStyle where Self == ESwitchToggleStyle {
    /// The Ember switch: `.toggleStyle(.ember)`.
    static var ember: ESwitchToggleStyle { ESwitchToggleStyle() }
}

private struct ESwitchBody: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.labelsVisibility) private var labelsVisibility

    var body: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            // `.labelsHidden()` (Settings rows) keeps the label for
            // accessibility only.
            if labelsVisibility != .hidden {
                configuration.label
                    .contentShape(Rectangle())
                    .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
                Spacer(minLength: EmberDesign.Spacing.s)
            }
            Button {
                configuration.isOn.toggle()
            } label: {
                EmptyView()
            }
            .buttonStyle(ESwitchTrackStyle(isOn: configuration.isOn))
        }
        .opacity(isEnabled ? 1 : EmberDesign.Control.disabledOpacity)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

private struct ESwitchTrackStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        ESwitchTrack(isOn: isOn, isPressed: configuration.isPressed)
    }
}

private struct ESwitchTrack: View {
    let isOn: Bool
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private typealias Control = EmberDesign.Control

    var body: some View {
        let size = Control.switchSize
        let inset = Control.switchKnobInset
        let diameter = size.height - inset * 2
        let stretch = isPressed && isEnabled && !reduceMotion ? Control.switchKnobPressStretch : 0
        let knobWidth = diameter + stretch
        let travel = size.width - inset * 2 - knobWidth
        let track = Capsule(style: .continuous)
        ZStack(alignment: .leading) {
            track.fill(.fill)
            track.fill(Color.accentColor).opacity(isOn ? 1 : 0)
            if contrast == .increased {
                track.strokeBorder(.separator, lineWidth: Control.hairlineWidth)
            }
            if reduceMotion {
                // Opacity only: the knob fades out at one end and in at the other.
                knob(width: knobWidth, height: diameter).offset(x: inset).opacity(isOn ? 0 : 1)
                knob(width: knobWidth, height: diameter).offset(x: inset + travel).opacity(isOn ? 1 : 0)
            } else {
                knob(width: knobWidth, height: diameter).offset(x: inset + (isOn ? travel : 0))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(EmberDesign.Motion.switchToggle(reduceMotion: reduceMotion), value: isOn)
        .animation(EmberDesign.Motion.switchPress(reduceMotion: reduceMotion), value: isPressed)
        .contentShape(.focusEffect, track)
        .frame(minWidth: Control.minimumHitTarget, minHeight: Control.minimumHitTarget)
        .contentShape(.interaction, Rectangle())
    }

    private func knob(width: CGFloat, height: CGFloat) -> some View {
        // A hairline instead of a drop shadow: no SwiftUI shadows on chrome.
        Capsule(style: .continuous)
            .fill(Control.switchKnobFill)
            .overlay(Capsule(style: .continuous).strokeBorder(.tertiary, lineWidth: Control.switchKnobStrokeWidth))
            .frame(width: width, height: height)
    }
}
