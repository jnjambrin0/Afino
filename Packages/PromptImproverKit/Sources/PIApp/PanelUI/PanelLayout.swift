import PIDesign
import SwiftUI

/// The few panel measurements `EmberDesign` does not have. Everything else comes from the
/// design tokens; views never use a literal radius, spacing, colour or duration.
nonisolated enum PanelLayout {
    // MARK: Geometry

    /// From the panel's edge to the first character of the compose input, the origin row, the
    /// footer's "For" label and the setup card.
    static let textLeadingInset: CGFloat = 22
    /// Between the content inset and the compose text: `textLeadingInset − contentInset`.
    static var inputTextPadding: CGFloat { textLeadingInset - EmberDesign.Panel.contentInset }

    /// On a short screen the panel moves up to keep `minUsableHeight` of room, but its top edge
    /// never comes closer than this to the top of the visible frame.
    static let minimumTopOffset: CGFloat = 24

    /// The add-a-key card replaces the whole panel (680 × 232).
    static let setupHeight: CGFloat = 232

    /// History: the filter row, the rows, how many show before the list scrolls, and the room the
    /// empty state takes (three rows).
    static let historyFilterHeight: CGFloat = 52
    static let historyRowHeight: CGFloat = 42
    static let historyVisibleRows = 8
    static let historyEmptyRows = 3
    /// Vertical breathing room above and below the list rows.
    static var historyListPadding: CGFloat { EmberDesign.Spacing.xs }

    /// The expanded original in the origin row shows at most this many lines.
    static let originMaxLines = 6
    /// One line of `.body`: the origin row is 12 + 16 + 12 = 40 tall.
    static let originLineHeight: CGFloat = 16
    /// The refine instruction after the draft in the origin row ("· Shorter") stops at this width.
    static let instructionMaxWidth: CGFloat = 200

    /// The error glyph in the well.
    static let errorGlyphFont: Font = .title3.weight(.medium)

    /// Width of the refine field's slot before it gives way to the buttons.
    static let refineFieldMinWidth: CGFloat = 120

    // MARK: Timing

    /// A height change of more than one line in the compose input (a paste) eases over this long.
    static let pasteResizeDuration: TimeInterval = 0.18
    /// The header's expand/collapse of the original uses the same short ease.
    static var originToggleDuration: TimeInterval { pasteResizeDuration }
    /// "Thinking…" adds the elapsed seconds once a run has gone this long without text.
    static let elapsedThreshold: TimeInterval = 5
    /// "Key works" stays on screen this long before the panel moves on.
    static let keyAcceptedHold: Duration = .milliseconds(800)
    /// A key saved without a check keeps its note a little longer.
    static let keyUnverifiedHold: Duration = .milliseconds(1600)
}
