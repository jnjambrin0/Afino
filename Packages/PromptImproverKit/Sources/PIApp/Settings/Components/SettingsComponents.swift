import PIDesign
import SwiftUI

// The building blocks of every Settings pane. A pane is a large title and a few titled groups;
// each group is one card of rows separated by inset hairlines, with explanations in short row
// subtitles or in a footer under the card, never in paragraphs between controls.

/// A pane: its large title, then its sections, scrolling under the transparent title bar.
///
/// The content keeps the same width whether or not a legacy (always visible) scroller takes room
/// at the trailing edge: the trailing padding gives back what the scroller takes, so switching
/// between a pane that scrolls and one that does not never moves the cards' edge.
struct SettingsPaneContainer<Content: View>: View {
    let title: String
    let content: Content

    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// The width a legacy scroller takes from the content (0 with overlay scrollers).
    private var scrollerWidth: CGFloat {
        guard viewportWidth > 0, contentWidth > 0 else { return 0 }
        return max(viewportWidth - contentWidth, 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EmberDesign.Settings.sectionSpacing) {
                Text(verbatim: title)
                    .font(SettingsLayout.paneTitleFont)
                    .tracking(SettingsLayout.paneTitleTracking)
                    .padding(.leading, EmberDesign.Settings.headerInset)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .toggleStyle(.ember)
            .padding(.leading, EmberDesign.Settings.contentPadding)
            .padding(.trailing, SettingsLayout.trailingContentPadding(scrollerWidth: scrollerWidth))
            .padding(.top, EmberDesign.Settings.titleBarClearance)
            .padding(.bottom, EmberDesign.Settings.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { viewportWidth = $0 }
        .scrollIndicators(.automatic)
        // The scroller starts below the title bar, level with the sidebar's first row.
        .contentMargins(.top, EmberDesign.Settings.titleBarClearance, for: .scrollIndicators)
        .contentMargins(.bottom, EmberDesign.Settings.sidebarInset, for: .scrollIndicators)
    }
}

/// A titled group: an optional sentence-case header, one card whose rows are separated by inset
/// hairlines, and an optional footer under the card.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            if let title {
                ESectionHeader(title)
                    .padding(.leading, EmberDesign.Settings.headerInset)
            }

            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            SettingsDivider()
                        }
                        row
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardBackground()

            if let footer {
                SettingsFooter(footer)
            }
        }
    }
}

extension View {
    /// The card behind a section's rows: a quiet fill with a hairline, like System Settings'
    /// grouped forms.
    func settingsCardBackground() -> some View {
        modifier(SettingsCardBackground())
    }

    /// The insets and minimum height of a row.
    func settingsRowPadding(compact: Bool = false) -> some View {
        padding(.horizontal, EmberDesign.Settings.rowHorizontalPadding)
            .padding(
                .vertical,
                compact ? EmberDesign.Settings.compactRowVerticalPadding : EmberDesign.Settings.rowVerticalPadding
            )
            .frame(
                minHeight: compact ? EmberDesign.Settings.compactRowMinHeight : EmberDesign.Settings.rowMinHeight,
                alignment: .leading
            )
    }
}

private struct SettingsCardBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: EmberDesign.Settings.cardRadius, style: .continuous)
        content
            .background(shape.fill(.fill.quinary))
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? AnyShapeStyle(.separator) : AnyShapeStyle(.separator.opacity(EmberDesign.Card.hairlineOpacity)),
                    lineWidth: contrast == .increased ? EmberDesign.Materials.wellStrokeWidth : EmberDesign.Control.hairlineWidth
                )
            }
    }
}

/// The hairline between two rows, inset like System Settings.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(EmberDesign.Card.hairlineOpacity))
            .frame(height: EmberDesign.Control.hairlineWidth)
            .padding(.leading, EmberDesign.Settings.rowHorizontalPadding)
            .accessibilityHidden(true)
    }
}

/// Secondary text under a card.
struct SettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(SettingsLayout.subtitleFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, EmberDesign.Settings.headerInset)
    }
}

/// One row: a title with an optional one-line subtitle, and the control on the trailing edge.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var compact = false
    @ViewBuilder var accessory: Accessory

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .center, spacing: EmberDesign.Spacing.m) {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
                Text(verbatim: title)
                    .font(.body)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(SettingsLayout.subtitleFont)
                        .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .settingsRowPadding(compact: compact)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A row whose control is a switch. The title is the switch's accessibility label.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(isOn: $isOn) { Text(verbatim: title) }
                .labelsHidden()
                .toggleStyle(.ember)
        }
    }
}

/// Free content inside a card (an editor, a set of chips), with the row insets.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsRowPadding()
    }
}

/// A row that is a link: its title, and a trailing arrow (↗ to the web, › within the app).
struct SettingsLinkRow: View {
    enum Destination {
        case web
        case inApp
    }

    let title: String
    var destination: Destination = .web
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: EmberDesign.Spacing.m) {
                Text(verbatim: title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: destination == .web ? "arrow.up.right" : "chevron.right")
                    .font(EmberDesign.Typography.hint.weight(.semibold))
                    .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .settingsRowPadding()
            .contentShape(.interaction, Rectangle())
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: EmberDesign.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(destination == .web ? .isLink : .isButton)
    }
}

/// "Cleared ✓": what a one-shot button turns into once it has done its job.
struct SettingsDoneLabel: View {
    let title: String

    var body: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: "checkmark")
                .foregroundStyle(EmberDesign.Status.positive)
        }
        .font(EmberDesign.Typography.button)
        .foregroundStyle(.secondary)
        // Lined up with the button it replaces: same height, its label where the title was.
        .padding(.horizontal, EmberDesign.Control.horizontalPadding)
        .frame(minHeight: EmberDesign.Control.minimumHitTarget)
        .accessibilityElement(children: .combine)
    }
}

/// A one-shot button that turns into a done label: the two crossfade in place, trailing-aligned,
/// so nothing else in the row moves.
struct SettingsOneShotButton: View {
    let title: String
    let doneTitle: String
    let isDone: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            if isDone {
                SettingsDoneLabel(title: doneTitle)
                    .transition(.opacity)
            } else {
                Button(title, action: action)
                    .buttonStyle(.ember(.secondary))
                    .disabled(isDisabled)
                    .transition(.opacity)
            }
        }
        .animation(EmberDesign.Motion.stateCrossfade, value: isDone)
    }
}
