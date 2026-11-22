import PIDesign
import SwiftUI

/// Fonts and measures only Settings uses, which `EmberDesign.Settings` does not define. Everything
/// else in Settings comes from the `EmberDesign` tokens.
enum SettingsLayout {
    /// The large title at the top of each pane.
    static let paneTitleFont: Font = .title.weight(.semibold)
    static let paneTitleTracking: CGFloat = -0.2

    /// Row subtitles and the notes under cards: 11 pt, as System Settings sets them (10 pt
    /// secondary text measured only 3.1:1 contrast on a light card).
    static let subtitleFont: Font = .subheadline

    /// The provider name above each API key field.
    static let providerNameFont: Font = .body.weight(.medium)
    /// The resolved model id under the model chips.
    static let modelIDFont: Font = .caption.monospaced()
    /// The app name in About.
    static let appNameFont: Font = .title3.weight(.semibold)

    /// Selects, the model id field and the shortcut recorder share one width, so their edges line
    /// up from row to row.
    static let trailingControlWidth: CGFloat = 200
    /// A select's minimum label width: the shared width less the button's own padding.
    static var selectMinWidth: CGFloat { trailingControlWidth - EmberDesign.Control.horizontalPadding * 2 }
    /// The free-text model id field.
    static var modelIDFieldWidth: CGFloat { trailingControlWidth }
    /// The shortcut recorder.
    static var recorderWidth: CGFloat { trailingControlWidth }

    /// The trailing padding of a pane's content: what a legacy scroller takes is given back, so
    /// the content is as wide with the scroller as without it (never tighter than a small step).
    static func trailingContentPadding(scrollerWidth: CGFloat) -> CGFloat {
        max(EmberDesign.Settings.contentPadding - scrollerWidth, EmberDesign.Spacing.s)
    }

    /// The instructions editor shows at least this many lines.
    static let instructionsMinLines = 8
    /// The instructions counter turns orange at this share of the limit.
    static let instructionsWarningFraction = 0.9
}
