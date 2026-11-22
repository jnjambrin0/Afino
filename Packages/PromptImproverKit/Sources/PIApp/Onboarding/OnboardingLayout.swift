import AppKit
import PIDesign
import SwiftUI

/// The few measurements and timings of the welcome window that `EmberDesign` has no token for.
/// Views in `Onboarding/` use these and the Ember tokens only: `OnboardingDesignLintTests` fails
/// on a literal colour, radius, spacing, padding or duration anywhere else in this folder.
nonisolated enum OnboardingLayout {
    // MARK: Window

    /// One size for every step, so nothing moves when a step changes. As wide as the panel plus
    /// a margin, tall enough for the keyboard step.
    static let windowSize = CGSize(width: 720, height: 600)
    /// Where the window sits on the screen it opens on: centred across, this fraction of the free
    /// height up from the bottom (a little above the middle, as `NSWindow.center()` does).
    static let verticalPlacement: CGFloat = 0.58

    /// Between the window's edges and the content.
    static let horizontalPadding: CGFloat = 44
    /// The band under the hidden title bar: the Skip link sits in it.
    static let topBarHeight: CGFloat = 48
    /// Back, the progress and the step's button.
    static let footerHeight: CGFloat = 72
    /// The keyboard step's list runs closer to the edges than the text.
    static let wideContentInset: CGFloat = 30
    /// Title and subtitle never run wider than this.
    static let textMaxWidth: CGFloat = 540
    /// Between the subtitle and what the step shows.
    static let contentTopSpacing: CGFloat = 28

    static let titleFont: Font = .largeTitle.weight(.semibold)
    static let subtitleFont: Font = .title3
    /// The facts and footnotes under a step's content.
    static let noteFont: Font = .callout

    // MARK: Progress

    static let progressDotSize: CGFloat = 6
    /// The current step's mark is a short bar instead of a dot.
    static let progressCurrentWidth: CGFloat = 20

    // MARK: Step 1 — the panel illustration

    /// The illustrated panel: narrower than the real one, with the real one's insets and fonts.
    static let illustrationWidth: CGFloat = 560
    /// How long the caret breathes ("thinking") before the text starts to arrive.
    static let illustrationThinking: Duration = .milliseconds(1500)
    /// The text arrives a word at a time, at this pace (a calm stream).
    static let illustrationWordInterval: Duration = .milliseconds(55)
    /// Before the "Copied" check, once the last word is in.
    static let illustrationSettle: Duration = .milliseconds(350)

    /// The stage the illustrated panel floats on, and the faint window under it: its dots, and
    /// its lines of text as fractions of the width (0: a blank line).
    static let stageHeight: CGFloat = 300
    static let stageDotSize: CGFloat = 8
    static let stageLineHeight: CGFloat = 7
    static let stageLineSpacing: CGFloat = 11
    static let stageLineWidths: [CGFloat] = [0.58, 0.86, 0.74, 0.91, 0.4, 0, 0.8, 0.67, 0.88, 0.52, 0, 0.73, 0.6]

    // MARK: Step 2 — the key

    static let keyCardWidth: CGFloat = 540
    /// The card and its notes, with room for a one-line message under the field; a longer one
    /// (or "Use OpenAI") runs into the free space below without moving anything above.
    static let keyBlockHeight: CGFloat = 212

    // MARK: Step 3 — the shortcut

    /// The large key caps of the activation shortcut: as tall as they are wide, a modifier wider.
    static let heroCapSize: CGFloat = 80
    static let heroModifierCapWidth: CGFloat = 116
    static let heroCapFont: Font = .system(size: 34, weight: .medium)
    static let heroModifierGlyphFont: Font = .title.weight(.medium)
    static let heroModifierWordFont: Font = .callout.weight(.medium)
    static let heroCapRadius: CGFloat = 12
    /// The dashed outline of an empty cap (no shortcut yet).
    static let emptyCapStroke = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
    static let heroCapSpacing: CGFloat = 10
    /// The caps dip to this scale and spring back when the shortcut is pressed.
    static let heroCapPressedScale: CGFloat = 0.92
    static let heroCapPressDuration: Duration = .milliseconds(120)
    static let successFont: Font = .title3.weight(.medium)
    /// Fixed so the step does not move when the hint turns into the success line.
    static let tryLineHeight: CGFloat = 28

    // MARK: Step 4 — the keys

    /// Key caps in the list: a size up from the panel's hint caps, for reading at a glance.
    static let guideCapHeight: CGFloat = 22
    static let guideCapMinWidth: CGFloat = 22
    static let guideCapFont: Font = .callout.weight(.medium)
    static let guideLabelFont: Font = .body
    static let guideGroupFont: Font = .subheadline.weight(.semibold)
    /// The group names' column.
    static let guideGroupColumnWidth: CGFloat = 100
    static let guideRowSpacing: CGFloat = 10
    static let guideColumnSpacing: CGFloat = 12
    /// Extra room before a line's second shortcut, so the two read as two.
    static let guidePairSpacing: CGFloat = 22
    /// The menu bar glyph in the last line.
    static let menuBarGlyphSize: CGFloat = 14

    // MARK: Motion

    /// How far a step slides as it comes in (opacity only under Reduce Motion).
    static let stepSlide: CGFloat = 18
}
