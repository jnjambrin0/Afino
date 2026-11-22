import SwiftUI

// Ember surfaces: wells for text-dense areas, cards, section headers, rows,
// inline messages and toasts.

public extension View {
    /// The surface of a floating card (a menu, a dialog): Liquid Glass with a backing fill under
    /// the content. The fill belongs to the card, so it fades in and out with the card's text —
    /// glass alone materializes on its own timeline, leaving the text over the content below for
    /// a few frames — and a coloured control under the card cannot glow through as a second
    /// highlight. Opaque under Increase Contrast or Reduce Transparency.
    func emberFloatingCardSurface(cornerRadius: CGFloat) -> some View {
        modifier(EFloatingCardSurface(cornerRadius: cornerRadius))
    }

    /// The well material behind this view: `windowBackgroundColor` at the well
    /// opacity, opaque under Increase Contrast or Reduce Transparency, plus a
    /// 1 pt separator stroke under Increase Contrast.
    func emberWellBackground(radius: CGFloat = EmberDesign.Radius.well) -> some View {
        modifier(EWellBackground(radius: radius))
    }
}

private struct EWellBackground: ViewModifier {
    let radius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let strokeWidth = EmberDesign.Materials.wellStrokeWidth(contrast: contrast)
        content
            .background(
                shape.fill(EmberDesign.Materials.wellFill(
                    colorScheme: colorScheme,
                    contrast: contrast,
                    reduceTransparency: reduceTransparency
                ))
            )
            .overlay {
                if strokeWidth > 0 {
                    shape.strokeBorder(EmberDesign.Materials.wellStroke, lineWidth: strokeWidth)
                }
            }
    }
}

private struct EFloatingCardSurface: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(EmberDesign.Glass.cardFill(
                colorScheme: colorScheme,
                contrast: contrast,
                reduceTransparency: reduceTransparency
            )))
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(EmberDesign.Materials.wellStroke, lineWidth: EmberDesign.Materials.wellStrokeWidth)
                }
            }
            .glassEffect(.regular, in: shape)
    }
}

/// A calm, solid reading surface on the glass, concentric with the panel: the
/// draft floats on the glass, the improved prompt lands on a well. Pads nothing;
/// the caller insets its content (`Panel.wellHorizontalPadding` …).
public struct EWell<Content: View>: View {
    public var radius: CGFloat
    public var content: Content

    public init(radius: CGFloat = EmberDesign.Radius.well, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content.emberWellBackground(radius: radius)
    }
}

/// A grouped block of settings or content.
public struct ECard<Content: View>: View {
    public var padding: CGFloat
    public var content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    public init(padding: CGFloat = EmberDesign.Card.padding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .emberWellBackground(radius: EmberDesign.Radius.medium)
        .overlay {
            // The well adds its own stroke under Increase Contrast.
            if contrast != .increased {
                RoundedRectangle(cornerRadius: EmberDesign.Radius.medium, style: .continuous)
                    .strokeBorder(.separator.opacity(EmberDesign.Card.hairlineOpacity), lineWidth: EmberDesign.Control.hairlineWidth)
            }
        }
    }
}

/// Sentence-case section title (never uppercase), optionally with a note.
public struct ESectionHeader: View {
    public let title: String
    public var subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
            Text(verbatim: title)
                .font(EmberDesign.Typography.sectionHeader)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(EmberDesign.Typography.fieldHelp)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A labelled row inside a card: title (and help) on the left, the control on
/// the right.
public struct ERow<Accessory: View>: View {
    public let title: String
    public var help: String?
    public var accessory: Accessory

    public init(_ title: String, help: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.help = help
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: EmberDesign.Spacing.m) {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
                Text(verbatim: title)
                    .font(.body)
                if let help {
                    Text(verbatim: help)
                        .font(EmberDesign.Typography.fieldHelp)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
    }
}

/// An inline message: error (red), warning (orange) or note (the user's accent
/// colour), on a faint fill of the same tint. Always a glyph and words, never
/// colour alone.
public struct EInlineMessage: View {
    public enum Tone: Sendable {
        case error
        case warning
        case note
    }

    public let message: String
    public var tone: Tone

    public init(_ message: String, tone: Tone = .error) {
        self.message = message
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
            Image(systemName: symbol)
                .font(EmberDesign.Typography.messageGlyph)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(EmberDesign.Typography.message)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, EmberDesign.Spacing.m)
        .padding(.vertical, EmberDesign.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: EmberDesign.Radius.medium, style: .continuous)
                .fill(tint.opacity(EmberDesign.Control.destructiveFillOpacity))
        )
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch tone {
        case .error: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch tone {
        case .error: EmberDesign.Status.negative
        case .warning: EmberDesign.Status.caution
        case .note: Color.accentColor
        }
    }
}

/// A glass capsule with a message and an optional action ("Undo ⌘Z").
/// Present it with `Motion.toastTransition(reduceMotion:)` and dismiss it
/// after `Motion.toastLifetime`.
public struct EToast: View {
    public let message: String
    public var symbol: String?
    public var actionTitle: String?
    public var actionChord: KeyChord?
    public var action: () -> Void

    public init(
        _ message: String,
        symbol: String? = nil,
        actionTitle: String? = nil,
        actionChord: KeyChord? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.message = message
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.actionChord = actionChord
        self.action = action
    }

    public var body: some View {
        HStack(spacing: EmberDesign.Spacing.m) {
            HStack(spacing: EmberDesign.Spacing.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: message)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(EmberDesign.Typography.toast)

            if let actionTitle {
                Button(action: action) {
                    EButtonLabel(actionTitle, chord: actionChord)
                }
                .buttonStyle(.ember(.ghost, size: .small))
            }
        }
        .padding(.leading, EmberDesign.Spacing.l)
        .padding(.trailing, actionTitle == nil ? EmberDesign.Spacing.l : EmberDesign.Spacing.xs)
        .padding(.vertical, EmberDesign.Spacing.xs)
        .frame(minHeight: EmberDesign.Control.height + EmberDesign.Spacing.s)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
