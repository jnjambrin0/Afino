import PIDesign
import SwiftUI

/// What every step shares: its title and subtitle at the same place at the top, then what the
/// step shows, centred in the room left above the footer.
struct WelcomeStepLayout<Content: View>: View {
    let step: WelcomeStep
    let subtitle: String
    /// The keyboard step's list takes a little more of the width than the text above it.
    var contentInset: CGFloat = OnboardingLayout.horizontalPadding
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: OnboardingLayout.contentTopSpacing) {
            VStack(spacing: EmberDesign.Spacing.s) {
                Text(verbatim: step.title)
                    .font(OnboardingLayout.titleFont)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .font(OnboardingLayout.subtitleFont)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: OnboardingLayout.textMaxWidth)
            .padding(.horizontal, OnboardingLayout.horizontalPadding)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, contentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A quiet line under a step's content: a symbol and a sentence.
struct WelcomeNote: View {
    let symbol: String
    let text: String
    var tint: AnyShapeStyle = AnyShapeStyle(.tertiary)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: EmberDesign.Card.menuGlyphColumn)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(OnboardingLayout.noteFont)
        .accessibilityElement(children: .combine)
    }
}
