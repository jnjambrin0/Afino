import PICore
import PIDesign
import PIProviders
import SwiftUI

/// Step 2: why a key, which provider, the key field Settings uses, and where the key lives.
/// Content grows from the top: a message under the field pushes nothing above it.
struct WelcomeKeyStepView: View {
    let model: WelcomeKeyStepModel
    let openURL: (URL) -> Void

    var body: some View {
        WelcomeStepLayout(step: .apiKey, subtitle: OnboardingStrings.text("welcome.key.subtitle")) {
            VStack(spacing: EmberDesign.Spacing.l) {
                EChoiceChips(
                    OnboardingStrings.text("welcome.key.provider"),
                    options: model.providers,
                    selection: Binding(get: { model.provider }, set: { model.select($0) }),
                    title: Self.title(of:)
                )
                .fixedSize()

                // The field's message and "Use OpenAI" grow into room kept for them: centred as
                // it is, nothing above the card moves when they come and go.
                VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
                    VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
                        EKeyField(model: model.entry, onRemove: model.requestRemoval, openURL: openURL)
                            // A field of its own per provider (its focus, its secure text).
                            .id(model.provider)
                        if let other = model.suggestedProvider {
                            Button(OnboardingStrings.text("welcome.key.useOther", other.displayName)) {
                                Task { await model.useSuggestedProvider() }
                            }
                            .buttonStyle(.ember(.secondary, size: .small))
                        }
                    }
                    .padding(EmberDesign.Card.padding)
                    .welcomeCard()
                    notes
                        .padding(.horizontal, EmberDesign.Spacing.xs)
                }
                .frame(width: OnboardingLayout.keyCardWidth)
                .frame(height: OnboardingLayout.keyBlockHeight, alignment: .top)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            WelcomeNote(symbol: "lock.fill", text: OnboardingStrings.text("welcome.key.privacy", model.provider.displayName))
            statusNote
        }
    }

    /// What the user is told about going on: ready, or that the key can wait. Always laid out,
    /// so the notes do not move while a key is being checked.
    @ViewBuilder
    private var statusNote: some View {
        if case .ready = model.status, let line = model.statusLine {
            WelcomeNote(symbol: "checkmark.circle.fill", text: line, tint: AnyShapeStyle(EmberDesign.Status.positive))
        } else if let line = model.statusLine {
            WelcomeNote(symbol: "clock", text: line)
        } else {
            WelcomeNote(symbol: "clock", text: OnboardingStrings.text("welcome.key.later.note"))
                .hidden()
        }
    }

    static func title(of provider: ProviderID) -> String {
        switch provider {
        case .anthropic: OnboardingStrings.text("welcome.key.provider.anthropic")
        case .openai: OnboardingStrings.text("welcome.key.provider.openai")
        }
    }
}
