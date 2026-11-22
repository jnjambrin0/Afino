import AppKit
import SwiftUI

/// The Ember design tokens. Every size, spacing, radius, opacity and duration the kit draws with
/// lives in `Tokens/`: this file, `EmberDesign+Brand.swift` and `EmberDesign+Motion.swift`.
///
/// Colours are system colours and hierarchical shape styles (`.primary` … `.quinary`,
/// `.separator`, `.fill.*`, the emphasized selection pair, the user's accent colour), plus the
/// three brand colours in `Brand`, so Light and Dark, Increase Contrast, Reduce Transparency and
/// the accent colour work without extra code. Opacities applied to system colours are tokens too.
/// Kit views never use a literal radius, spacing, font size or colour: `DesignSystemLintTests`
/// fails on one anywhere in `PIDesign` outside `Tokens/`.
public nonisolated enum EmberDesign {
    /// The spacing scale: a 4/8 pt grid with 2 pt and 12 pt half steps.
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
    }

    /// One concentric radius scale, 6 / 10 / 16 / 26 (the window), plus the few small marks that
    /// sit outside it.
    public enum Radius {
        /// The panel's outer corner radius. AppKit has no public API for the system window
        /// radius on macOS 26, so this matches the large window corners measured on macOS 26.
        public static let window: CGFloat = 26

        /// Key caps and compact chrome outside the panel's concentric chain.
        public static let keyCap: CGFloat = 4

        /// The monogram tile of a target chip or menu row.
        public static let monogram: CGFloat = 5

        /// The accent caret's rounded ends.
        public static let caret: CGFloat = 1

        /// Small controls.
        public static let small: CGFloat = 6
        /// Controls and cards inside the panel.
        public static let medium: CGFloat = 10
        /// Floating cards (menus, dialogs) and wells.
        public static let large: CGFloat = 16

        /// The radius of a shape inset `inset` points inside a container with radius `outer`, so
        /// both share the same corner centre. Never negative.
        public static func inner(outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, 0)
        }

        /// Wells sit at the panel's content inset, concentric with the window.
        public static var well: CGFloat {
            inner(outer: window, inset: Panel.contentInset)
        }

        /// Sidebar rows, icon tiles and other rectangular controls placed at the panel's content
        /// inset plus one small step. Buttons, chips, selects and switches are capsules
        /// (`Capsule(style: .continuous)`) instead: at 28 pt that is both the macOS 26
        /// large-control shape and concentric with the panel's corners.
        public static var control: CGFloat {
            inner(outer: window, inset: Panel.contentInset + Spacing.s)
        }

        /// Text fields: a soft rounded rectangle that sits beside capsule buttons without looking
        /// boxy. Fields stay rectangles, as on macOS; only search-like fields are capsules.
        public static var field: CGFloat { medium }

        /// A highlighted menu row, concentric with its card (`large`, inset by
        /// `Card.menuPadding`).
        public static var menuRow: CGFloat {
            inner(outer: large, inset: Card.menuPadding)
        }
    }

    /// The launcher panel's geometry.
    public enum Panel {
        /// The single column is this wide, always.
        public static let width: CGFloat = 680
        /// Inset between the panel edge and its content (header, wells, footer).
        public static let contentInset: CGFloat = 10
        /// The top edge sits this fraction of the visible-frame height below its top; the panel
        /// only grows downward from there.
        public static let topOffsetFraction: CGFloat = 0.22

        /// One line of the compose input (`.title3`).
        public static let inputLineHeight: CGFloat = 20
        /// The compose input with one line.
        public static let inputMinHeight: CGFloat = 52
        /// The compose input grows to this many lines, then scrolls.
        public static let inputMaxLines = 10

        /// The result header (source row, status).
        public static let headerHeight: CGFloat = 40
        /// The footer (target chip, refine field, primary action).
        public static let footerHeight: CGFloat = 44

        /// Horizontal padding inside the result well.
        public static let wellHorizontalPadding: CGFloat = 16
        /// Vertical padding inside the result well.
        public static let wellVerticalPadding: CGFloat = 14
        /// The result well never starts smaller than this (three lines).
        public static let wellMinHeight: CGFloat = 91
        /// The notice row under the well (partial result, stopped).
        public static let noticeRowHeight: CGFloat = 36

        /// The panel is never taller than this…
        public static let maxHeightCap: CGFloat = 720
        /// …and keeps this far from the bottom of the visible frame.
        public static let bottomMargin: CGFloat = 24
        /// The smallest panel height the layout is designed for.
        public static let minUsableHeight: CGFloat = 420

        /// The compose state with one input line: input plus footer (680 × 96).
        public static var composeHeight: CGFloat {
            inputMinHeight + footerHeight
        }

        /// The compose input's height for `lines` lines of text, clamped to `1...inputMaxLines`.
        public static func inputHeight(forLines lines: Int) -> CGFloat {
            let clamped = min(max(lines, 1), inputMaxLines)
            return inputMinHeight + CGFloat(clamped - 1) * inputLineHeight
        }
    }

    /// The paced reveal of a streaming result (PIApp's `StreamTextView` and
    /// `StreamRevealBuffer`).
    public enum Stream {
        /// Deltas are buffered and released on this tick.
        public static let drainInterval: TimeInterval = 0.033
        /// Each tick releases this fraction of what is pending…
        public static let drainFraction: Double = 0.2
        /// …but never fewer than this many characters.
        public static let minimumRelease = 2
        /// Each released run fades in over this long. Only rendering attributes change, so the
        /// text never reflows.
        public static let fadeDuration: TimeInterval = 0.1
        /// The well follows the text's height with this time constant (it only grows).
        public static let followTimeConstant: TimeInterval = 0.08
        /// Scrolling up further than this from the bottom releases the anchor and shows
        /// "Jump to latest".
        public static let unpinDistance: CGFloat = 24
        /// Height of the fade at the top and bottom edges of a scrolled well.
        public static let edgeFade: CGFloat = 12
        /// A release may extend this many characters to end on a word boundary.
        public static let wordBoundaryLookahead = 12

        /// How many characters one tick releases with `pending` waiting:
        /// `max(2, ceil(pending × 0.2))`, never more than `pending`.
        public static func releaseCount(pending: Int) -> Int {
            guard pending > 0 else { return 0 }
            let fraction = Int((Double(pending) * drainFraction).rounded(.up))
            return min(pending, max(minimumRelease, fraction))
        }
    }

    /// Borderless key caps: documentation, not buttons.
    public enum KeyCap {
        public static let height: CGFloat = 18
        public static let minWidth: CGFloat = 18
        /// Padding on each side of a cap with more than one character ("Esc", "Space").
        public static let horizontalPadding: CGFloat = 5
        /// Caps on the selection fill (a highlighted menu row): the selection foreground at this
        /// opacity.
        public static let onSelectionOpacity: Double = 0.22
        /// Caps on the accent fill (a primary button): `Brand.onAccent` at this opacity.
        public static let onAccentOpacity: Double = 0.22
        /// Space between the caps of one shortcut.
        public static let capSpacing: CGFloat = 2
        /// Space between a group of caps and its label in a hint bar.
        public static let labelSpacing: CGFloat = 6
    }

    /// Text styles: semantic system styles, except the result body, which has a fixed size and
    /// line spacing. Text is proportional everywhere (prompts are prose); only code blocks in the
    /// result are monospaced.
    public enum Typography {
        /// The compose input on the glass.
        public static let input: Font = .title3
        /// The result body is 14 pt with 4 pt line spacing.
        public static let resultBodySize: CGFloat = 14
        public static let resultLineSpacing: CGFloat = 4
        public static var resultBody: Font { .system(size: resultBodySize) }
        /// The result body for the AppKit text view that streams it.
        public static var resultBodyNSFont: NSFont { .systemFont(ofSize: resultBodySize) }
        /// Code blocks in the result, at the body size.
        public static var resultCodeNSFont: NSFont {
            .monospacedSystemFont(ofSize: resultBodySize, weight: .regular)
        }

        public static let keyCap: Font = .caption.weight(.medium)
        /// Hint bars and quiet status text.
        public static let hint: Font = .caption
        /// SF Symbols in icon buttons.
        public static let chromeGlyph: Font = .body.weight(.medium)

        // Controls and surfaces.
        public static let button: Font = .body.weight(.medium)
        public static let buttonSmall: Font = .callout.weight(.medium)
        public static let fieldHelp: Font = .caption
        public static let sectionHeader: Font = .subheadline.weight(.semibold)
        public static let dialogTitle: Font = .title3.weight(.semibold)
        public static let menuItem: Font = .body
        public static let menuSection: Font = .caption.weight(.medium)
        /// The value shown in a select button (regular weight, like a pop-up button).
        public static let selectValue: Font = .body
        public static let toast: Font = .callout.weight(.medium)
        /// The message of an empty state.
        public static let emptyBody: Font = .callout
        /// The "Copied" label.
        public static let confirmation: Font = .title3.weight(.semibold)
        /// Inline messages and menu notes.
        public static let message: Font = .callout
        /// The glyph beside an inline message and a menu row's checkmark.
        public static let messageGlyph: Font = .callout.weight(.semibold)

        /// The target chip's name.
        public static let chipName: Font = .callout.weight(.medium)
        /// The letters inside a monogram tile.
        public static let monogram: Font = .caption.weight(.semibold)
        public static let badge: Font = .caption.weight(.medium)
    }

    /// Kit controls: buttons, fields, chips, selects and the switch.
    public enum Control {
        /// Every interactive element is at least this large on both axes.
        public static let minimumHitTarget: CGFloat = 28
        public static let iconButtonSize: CGFloat = 28
        public static let disabledOpacity: Double = 0.45
        /// A dimmed control: inactive but still usable.
        public static let dimmedOpacity: Double = 0.55
        public static let hairlineWidth: CGFloat = 0.5
        /// Regular buttons and selects.
        public static let height: CGFloat = 28
        /// Small buttons; they keep the full hit target.
        public static let smallHeight: CGFloat = 24
        public static let horizontalPadding: CGFloat = 12
        public static let smallHorizontalPadding: CGFloat = 9
        /// Fields are as tall as buttons and selects, so a row's controls line up.
        public static let fieldHeight: CGFloat = 28
        public static let fieldHorizontalPadding: CGFloat = 10
        public static let focusRingWidth: CGFloat = 2
        public static let invalidRingWidth: CGFloat = 1.5
        /// A pressed primary button darkens by this much.
        public static let pressedBrightness: Double = -0.06
        /// The faint red fill of a destructive button at rest, hovered and pressed. Inline
        /// messages use the resting value with their own tint.
        public static let destructiveFillOpacity: Double = 0.14
        public static let destructiveHoverFillOpacity: Double = 0.22
        public static let destructivePressedFillOpacity: Double = 0.3
        /// A capsule track with a round knob.
        public static let switchSize = CGSize(width: 36, height: 20)
        public static let switchKnobInset: CGFloat = 2
        /// While pressed, the knob stretches this much toward the other end, like the system
        /// switch.
        public static let switchKnobPressStretch: CGFloat = 5
        /// The switch knob is white in both appearances, like the system's.
        public static let switchKnobFill: Color = .white
        /// The knob's edge: `separatorColor` is too faint on the light off track.
        public static let switchKnobStrokeWidth: CGFloat = 0.5
        /// Choice and action chips.
        public static let chipHeight: CGFloat = 26
        public static var chipHorizontalPadding: CGFloat { smallHorizontalPadding + Spacing.xxs }
        /// The chevron of a select button.
        public static let selectChevron = "chevron.up.chevron.down"
    }

    /// Target chips and monogram tiles (`.fill.tertiary`, never glass).
    public enum Chip {
        /// The target chip is a 28 pt capsule.
        public static let targetHeight: CGFloat = 28
        /// Monogram tiles are square.
        public static let monogramSize: CGFloat = 18
        /// Wide letter pairs ("Gp") may shrink this much to fit the tile.
        public static let monogramMinimumScale: CGFloat = 0.8
        /// Space between the tile, the name and the key cap.
        public static let itemSpacing: CGFloat = 6
        public static let trailingPadding: CGFloat = 10
        /// With a key cap at the end, it sits this far from the edge.
        public static let trailingCapPadding: CGFloat = 5
        /// The tile is inset evenly on the leading edge.
        public static var leadingInset: CGFloat {
            (targetHeight - monogramSize) / 2
        }
    }

    /// Status badges (the state of an API key).
    public enum Badge {
        public static let horizontalPadding: CGFloat = 8
        public static let verticalPadding: CGFloat = 3
        /// Space between the glyph and the word.
        public static let glyphSpacing: CGFloat = 4
    }

    /// Cards: floating menus and dialogs, and the grouped `ECard`.
    public enum Card {
        /// The opacity of a card's hairline.
        public static let hairlineOpacity: Double = 0.6
        public static let padding: CGFloat = 16
        /// Inset between a menu card's edge and its rows.
        public static let menuPadding: CGFloat = 5
        public static let menuWidth: CGFloat = 264
        /// A select's card is at least this wide (or as wide as its button).
        public static let selectMenuMinWidth: CGFloat = 200
        public static let menuRowHeight: CGFloat = 28
        /// Space above and below the hairline between menu sections.
        public static let menuSectionSpacing: CGFloat = 4
        /// The leading symbol or monogram column of a menu row.
        public static let menuGlyphColumn: CGFloat = 20
        public static let dialogWidth: CGFloat = 380
        /// Floating cards stay this far inside the container's edges.
        public static let edgeMargin: CGFloat = 8
        /// The gap between an anchor (a select button) and its card.
        public static let anchorGap: CGFloat = 4
    }

    /// The Settings window: 760 × 560 with a glass sidebar.
    public enum Settings {
        /// Grouped cards, as System Settings draws them.
        public static let cardRadius: CGFloat = 12
        public static let windowSize = CGSize(width: 760, height: 560)
        public static let sidebarWidth: CGFloat = 196
        public static let sidebarInset: CGFloat = 8
        public static let sidebarRowHeight: CGFloat = 30
        public static let contentPadding: CGFloat = 28
        public static let sectionSpacing: CGFloat = 22
        /// Grouped rows: insets, minimum height and the header and footer inset that lines text
        /// up with the card's corner.
        public static let rowHorizontalPadding: CGFloat = 16
        public static let rowVerticalPadding: CGFloat = 10
        public static let rowMinHeight: CGFloat = 44
        public static let headerInset: CGFloat = 4
        public static let appIconSize: CGFloat = 48
        /// Reference lists (Shortcuts) use tighter rows.
        public static let compactRowVerticalPadding: CGFloat = 6
        public static let compactRowMinHeight: CGFloat = 34
        /// Room for the traffic lights above the sidebar items.
        public static let titleBarClearance: CGFloat = 52
    }

    /// The "Copied" pill the panel shrinks into after Copy and Close.
    public enum Confirmation {
        /// Padding on each side of the check and label.
        public static let horizontalPadding: CGFloat = 22
        /// The pill's height; its width grows to fit the label.
        public static let pillHeight: CGFloat = 48
        public static let pillMinWidth: CGFloat = 180
        /// The checkmark's width as a multiple of its font's point size, for sizing the pill
        /// before it is drawn.
        public static let symbolWidthFactor: CGFloat = 1.2
        /// The pill's corner radius: a capsule from the start of the shrink.
        public static var pillRadius: CGFloat { pillHeight / 2 }
    }

    /// The accent caret (`EAccentCaret`).
    public enum Caret {
        public static let width: CGFloat = 2
        public static var cornerRadius: CGFloat { Radius.caret }
        /// Height when no line height is given (one `.title3` line).
        public static let defaultHeight: CGFloat = 18
    }

    /// The panel's Liquid Glass surface (`NSGlassEffectView`, `.regular` style) and the glass of
    /// floating cards.
    public enum Glass {
        /// The panel glass's `tintColor` is `windowBackgroundColor` at this alpha: it calms busy
        /// backdrops without losing the glass.
        public static let tintLight: CGFloat = 0.55
        public static let tintDark: CGFloat = 0.5
        /// Floating cards (menus, dialogs) over controls are tinted more than the panel, so a
        /// coloured control under them (a selected chip, a switch) cannot glow through the glass
        /// as a second highlight. Tuned over the Settings window.
        public static let cardTintLight: Double = 0.82
        public static let cardTintDark: Double = 0.86

        /// The panel glass's tint alpha for the appearance.
        public static func tintAlpha(isDark: Bool) -> CGFloat {
            isDark ? tintDark : tintLight
        }

        /// The backing fill of a floating card in `scheme`.
        public static func cardTint(for scheme: ColorScheme) -> Color {
            Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? cardTintDark : cardTintLight)
        }

        /// The backing fill of a floating card: the card tint, opaque under Increase Contrast or
        /// Reduce Transparency.
        public static func cardFill(
            colorScheme: ColorScheme,
            contrast: ColorSchemeContrast = .standard,
            reduceTransparency: Bool = false
        ) -> Color {
            if contrast == .increased || reduceTransparency {
                return Color(nsColor: .windowBackgroundColor)
            }
            return cardTint(for: colorScheme)
        }

        /// The scrim a dialog draws over the panel content.
        public static let scrimOpacity: Double = 0.18
        public static var scrim: Color { Color.black.opacity(scrimOpacity) }

        /// Text fields on the glass fill with the background style at this opacity.
        public static let fieldOpacityLight: Double = 0.7
        public static let fieldOpacityDark: Double = 0.22

        /// The field fill's opacity in `scheme`.
        public static func fieldOpacity(for scheme: ColorScheme) -> Double {
            scheme == .dark ? fieldOpacityDark : fieldOpacityLight
        }
    }

    /// Materials below the glass: wells (solid sheets), chips and tiles. Floating cards use
    /// `.glassEffect(.regular, in:)`; chips never use glass.
    public enum Materials {
        /// Wells: `windowBackgroundColor` at these opacities…
        public static let wellOpacityLight: Double = 0.6
        public static let wellOpacityDark: Double = 0.42
        /// …opaque under Increase Contrast or Reduce Transparency…
        public static let wellOpacityOpaque: Double = 1
        /// …with a 1 pt `separatorColor` stroke under Increase Contrast.
        public static let wellStrokeWidth: CGFloat = 1

        /// The well fill's opacity for the appearance and accessibility settings.
        public static func wellOpacity(
            colorScheme: ColorScheme,
            contrast: ColorSchemeContrast = .standard,
            reduceTransparency: Bool = false
        ) -> Double {
            if contrast == .increased || reduceTransparency {
                return wellOpacityOpaque
            }
            return colorScheme == .dark ? wellOpacityDark : wellOpacityLight
        }

        /// The well fill for the appearance and accessibility settings.
        public static func wellFill(
            colorScheme: ColorScheme,
            contrast: ColorSchemeContrast = .standard,
            reduceTransparency: Bool = false
        ) -> Color {
            Color(nsColor: .windowBackgroundColor).opacity(
                wellOpacity(colorScheme: colorScheme, contrast: contrast, reduceTransparency: reduceTransparency)
            )
        }

        /// The stroke width a well draws (0 for none).
        public static func wellStrokeWidth(contrast: ColorSchemeContrast) -> CGFloat {
            contrast == .increased ? wellStrokeWidth : 0
        }

        public static var wellStroke: Color { Color(nsColor: .separatorColor) }

        /// Chips, monogram tiles and quiet controls.
        public static func chipFill(isHovered: Bool) -> AnyShapeStyle {
            quietFill(isHovered: isHovered, isPressed: false)
        }

        /// Quiet controls (secondary buttons, chips, selects) step up the system fill scale:
        /// tertiary at rest, secondary under the pointer, primary while pressed.
        public static func quietFill(isHovered: Bool, isPressed: Bool) -> AnyShapeStyle {
            if isPressed { return AnyShapeStyle(.fill) }
            return isHovered ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary)
        }
    }

    /// The Apple-native emphasized selection pair, as `NSTableView` and Spotlight draw it. Do
    /// not replace it with the accent colour at low opacity.
    public enum Selection {
        /// Secondary text on the selection fill (a menu row's hint, its key caps) is the
        /// selection foreground at this opacity.
        public static let secondaryOpacity: Double = 0.8

        public static var background: Color {
            Color(nsColor: .selectedContentBackgroundColor)
        }

        public static var foreground: Color {
            Color(nsColor: .alternateSelectedControlTextColor)
        }

        public static var secondaryForeground: Color {
            foreground.opacity(secondaryOpacity)
        }
    }

    /// Semantic tints for status, always paired with a glyph and a word.
    public enum Status {
        public static var positive: Color { Color(nsColor: .systemGreen) }
        public static var negative: Color { Color(nsColor: .systemRed) }
        public static var caution: Color { Color(nsColor: .systemOrange) }
        public static var neutral: Color { Color(nsColor: .secondaryLabelColor) }
        /// Placeholder text in fields.
        public static var placeholder: Color { Color(nsColor: .placeholderTextColor) }
        /// The system keyboard focus colour, for focus rings the kit draws itself.
        public static var focusRing: Color { Color(nsColor: .keyboardFocusIndicatorColor) }
    }
}
