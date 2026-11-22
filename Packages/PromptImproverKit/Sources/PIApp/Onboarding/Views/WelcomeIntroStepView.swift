import PIDesign
import SwiftUI

/// Step 1: what Afino is, in one sentence, and the panel doing it.
struct WelcomeIntroStepView: View {
    let flow: WelcomeFlow
    let target: WelcomeIllustrationTarget

    var body: some View {
        WelcomeStepLayout(step: .welcome, subtitle: OnboardingStrings.text("welcome.intro.subtitle")) {
            WelcomeStage {
                WelcomeIllustration(target: target, hasPlayed: flow.hasPlayedIllustration) {
                    flow.hasPlayedIllustration = true
                }
            }
        }
    }
}

/// Where the illustrated panel appears: over a faint app window, a little below its top, as the
/// real panel appears over whatever the user is writing in. The glass has something to show
/// through. Decorative.
struct WelcomeStage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EmberDesign.Radius.large, style: .continuous)
        ZStack(alignment: .top) {
            backdrop
            content
                .padding(.top, OnboardingLayout.stageHeight * EmberDesign.Panel.topOffsetFraction)
        }
        .frame(maxWidth: .infinity)
        .frame(height: OnboardingLayout.stageHeight, alignment: .top)
        .clipShape(shape)
        .welcomeCard()
    }

    /// Someone else's window: three dots and a few lines of text, barely there.
    private var backdrop: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.stageLineSpacing) {
            HStack(spacing: EmberDesign.Spacing.xs + EmberDesign.Spacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(.fill.tertiary)
                        .frame(width: OnboardingLayout.stageDotSize, height: OnboardingLayout.stageDotSize)
                }
            }
            .padding(.bottom, EmberDesign.Spacing.s)
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: OnboardingLayout.stageLineSpacing) {
                    ForEach(Array(OnboardingLayout.stageLineWidths.enumerated()), id: \.offset) { _, fraction in
                        Capsule(style: .continuous)
                            .fill(.fill.quaternary)
                            .frame(width: proxy.size.width * fraction, height: OnboardingLayout.stageLineHeight)
                            .opacity(fraction > 0 ? 1 : 0)
                    }
                }
            }
        }
        .padding(EmberDesign.Spacing.l + EmberDesign.Spacing.xxs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
