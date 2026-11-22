import PIDesign
import SwiftUI

// Key caps for the welcome. `EKeyCap` is the panel's quiet 18 pt hint cap; the welcome puts the
// keys first, so it draws them a size up (the keyboard step) and as large physical caps (the
// shortcut step). Both are documentation, not buttons, and hidden from accessibility: the row or
// the group that holds them speaks the keys in words.

/// A key cap a size up from `EKeyCap`, for the keyboard step's list.
struct WelcomeKeyCap: View {
    let glyph: String

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EmberDesign.Radius.small, style: .continuous)
        Text(verbatim: glyph)
            .font(OnboardingLayout.guideCapFont)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, glyph.count > 1 ? EmberDesign.Spacing.s - EmberDesign.Spacing.xxs : 0)
            .frame(minWidth: OnboardingLayout.guideCapMinWidth, minHeight: OnboardingLayout.guideCapHeight)
            .background(shape.fill(.fill.secondary))
            .overlay {
                shape.strokeBorder(
                    .separator.opacity(contrast == .increased ? 1 : EmberDesign.Card.hairlineOpacity),
                    lineWidth: EmberDesign.Control.hairlineWidth
                )
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A row's keys: caps, what is typed first, and the mark between two keys that share modifiers.
struct WelcomeKeyTokens: View {
    let tokens: [WelcomeKeyToken]

    var body: some View {
        HStack(spacing: EmberDesign.KeyCap.capSpacing + EmberDesign.Spacing.xxs) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .cap(let glyph):
                    WelcomeKeyCap(glyph: glyph)
                case .typed(let sample):
                    Text(verbatim: OnboardingStrings.text("welcome.keys.typed", sample))
                        .font(OnboardingLayout.guideCapFont.italic())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, EmberDesign.Spacing.xxs)
                case .through:
                    Text(verbatim: "–")
                        .font(OnboardingLayout.guideCapFont)
                        .foregroundStyle(.tertiary)
                case .or:
                    Text(verbatim: "/")
                        .font(OnboardingLayout.guideCapFont)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// One large key cap of the activation shortcut, drawn as on a Mac keyboard: a modifier shows its
/// symbol in the top corner and its name at the bottom ("⌃" … "control"), so the shortcut reads
/// for someone who does not know the symbols; any other key shows its legend in the middle.
struct WelcomeHeroKeyCap: View {
    let cap: WelcomeHeroCap
    /// The shortcut was just pressed: the cap is outlined in the success tint.
    var isLit = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingLayout.heroCapRadius, style: .continuous)
        legend
            .background(shape.fill(.fill.secondary))
            .overlay {
                shape.strokeBorder(
                    isLit ? AnyShapeStyle(EmberDesign.Status.positive) : AnyShapeStyle(.separator.opacity(contrast == .increased ? 1 : EmberDesign.Card.hairlineOpacity)),
                    lineWidth: isLit ? EmberDesign.Control.focusRingWidth : EmberDesign.Control.hairlineWidth
                )
            }
            .fixedSize()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legend: some View {
        if let word = cap.word {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: cap.glyph)
                    .font(OnboardingLayout.heroModifierGlyphFont)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 0)
                Text(verbatim: word)
                    .font(OnboardingLayout.heroModifierWordFont)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, EmberDesign.Spacing.m)
            .padding(.vertical, EmberDesign.Spacing.s + EmberDesign.Spacing.xxs)
            .frame(width: OnboardingLayout.heroModifierCapWidth, height: OnboardingLayout.heroCapSize)
        } else {
            Text(verbatim: cap.glyph)
                .font(OnboardingLayout.heroCapFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, cap.glyph.count > 1 ? EmberDesign.Spacing.l : 0)
                .frame(minWidth: OnboardingLayout.heroCapSize, minHeight: OnboardingLayout.heroCapSize)
        }
    }
}

/// An empty key cap, dashed: where the shortcut will go once there is one.
struct WelcomeEmptyKeyCap: View {
    var isWide = false

    var body: some View {
        RoundedRectangle(cornerRadius: OnboardingLayout.heroCapRadius, style: .continuous)
            .strokeBorder(.tertiary, style: OnboardingLayout.emptyCapStroke)
            .frame(
                width: isWide ? OnboardingLayout.heroModifierCapWidth : OnboardingLayout.heroCapSize,
                height: OnboardingLayout.heroCapSize
            )
            .accessibilityHidden(true)
    }
}
