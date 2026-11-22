import SwiftUI

/// What a key cap is drawn on; the cap adapts its glyph and fill.
public enum EKeyCapBackdrop: Sendable {
    /// Glass, wells, quiet controls.
    case plain
    /// The emphasized selection fill (a highlighted menu row).
    case selection
    /// The accent fill (a primary button): caps in `Brand.onAccent`.
    case accent
}

public extension EnvironmentValues {
    /// The backdrop key caps in this subtree are drawn on. Primary buttons and
    /// highlighted menu rows set it; everything else leaves it `.plain`.
    @Entry var emberKeyCapBackdrop: EKeyCapBackdrop = .plain
}

/// One key cap. Caps are documentation, not buttons: borderless, quiet and
/// hidden from accessibility (the control they belong to carries the
/// shortcut). The one cap implementation for the panel, menus and Settings.
public struct EKeyCap: View {
    /// What the cap shows: a modifier glyph, a key name or a character.
    public let glyph: String

    @Environment(\.emberKeyCapBackdrop) private var backdrop

    public init(glyph: String) {
        self.glyph = glyph
    }

    public var body: some View {
        Text(verbatim: glyph)
            .font(EmberDesign.Typography.keyCap)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .frame(minWidth: EmberDesign.KeyCap.minWidth, minHeight: EmberDesign.KeyCap.height)
            .padding(.horizontal, glyph.count > 1 ? EmberDesign.KeyCap.horizontalPadding : 0)
            .background(
                RoundedRectangle(cornerRadius: EmberDesign.Radius.keyCap, style: .continuous)
                    .fill(fill)
            )
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var foreground: AnyShapeStyle {
        switch backdrop {
        case .plain: AnyShapeStyle(.secondary)
        case .selection: AnyShapeStyle(EmberDesign.Selection.secondaryForeground)
        case .accent: AnyShapeStyle(EmberDesign.Brand.onAccent)
        }
    }

    private var fill: AnyShapeStyle {
        switch backdrop {
        case .plain:
            AnyShapeStyle(.fill.tertiary)
        case .selection:
            AnyShapeStyle(EmberDesign.Selection.foreground.opacity(EmberDesign.KeyCap.onSelectionOpacity))
        case .accent:
            AnyShapeStyle(EmberDesign.Brand.onAccent.opacity(EmberDesign.KeyCap.onAccentOpacity))
        }
    }
}

/// The caps of a whole chord or recorded shortcut, side by side.
public struct EKeyCapGroup: View {
    public let caps: [String]

    /// Caps the caller has already named (a recorded shortcut).
    public init(caps: [String]) {
        self.caps = caps
    }

    public init(_ chord: KeyChord) {
        self.caps = ShortcutGlyphFormatter.caps(for: chord)
    }

    public var body: some View {
        HStack(spacing: EmberDesign.KeyCap.capSpacing) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, glyph in
                EKeyCap(glyph: glyph)
            }
        }
        .accessibilityHidden(true)
    }
}
