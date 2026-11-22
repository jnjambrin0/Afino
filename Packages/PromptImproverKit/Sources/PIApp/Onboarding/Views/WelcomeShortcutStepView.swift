import PIDesign
import SwiftUI

/// Step 3, the heart of the welcome: the shortcut that opens the panel from any app, as large key
/// caps, with an invitation to press it now. Pressing it is caught here (`WelcomeFlow
/// .activationShortcutPressed()`) and celebrated in place instead of opening the panel. The
/// recorder Settings uses changes it on the spot.
struct WelcomeShortcutStepView: View {
    let flow: WelcomeFlow
    let model: WelcomeShortcutStepModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        WelcomeStepLayout(step: .shortcut, subtitle: OnboardingStrings.text("welcome.shortcut.subtitle")) {
            VStack(spacing: EmberDesign.Spacing.xxl + EmberDesign.Spacing.s) {
                if model.caps.isEmpty {
                    absence
                } else {
                    hero
                }
                recorder
            }
            .padding(.bottom, EmberDesign.Spacing.s)
        }
        .onChange(of: flow.shortcutPressCount) { _, count in
            if count > 0 { press() }
        }
        .onChange(of: model.caps) {
            flow.shortcutDidChange()
        }
    }

    // MARK: The shortcut

    private var hero: some View {
        VStack(spacing: EmberDesign.Spacing.xl) {
            HStack(spacing: OnboardingLayout.heroCapSpacing) {
                ForEach(Array(model.heroCaps.enumerated()), id: \.offset) { _, cap in
                    WelcomeHeroKeyCap(cap: cap, isLit: flow.hasTriedShortcut)
                }
            }
            .scaleEffect(isPressed ? OnboardingLayout.heroCapPressedScale : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: OnboardingStrings.text("welcome.shortcut.spoken", model.spoken)))

            ZStack {
                if flow.hasTriedShortcut {
                    HStack(spacing: EmberDesign.Spacing.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(EmberDesign.Status.positive)
                            .accessibilityHidden(true)
                        Text(verbatim: OnboardingStrings.text("welcome.shortcut.success"))
                            .foregroundStyle(.primary)
                    }
                    .font(OnboardingLayout.successFont)
                    .transition(.opacity)
                } else {
                    Text(verbatim: OnboardingStrings.text("welcome.shortcut.try", model.compact))
                        .font(OnboardingLayout.successFont)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(height: OnboardingLayout.tryLineHeight)
            .animation(EmberDesign.Motion.contentCrossfade, value: flow.hasTriedShortcut)
            .accessibilityElement(children: .combine)
        }
    }

    /// No shortcut opens the panel: empty caps where it will go, why, and the recorder below.
    private var absence: some View {
        VStack(spacing: EmberDesign.Spacing.xl) {
            HStack(spacing: OnboardingLayout.heroCapSpacing) {
                WelcomeEmptyKeyCap(isWide: true)
                WelcomeEmptyKeyCap(isWide: true)
                WelcomeEmptyKeyCap()
            }
            Text(verbatim: model.absenceText ?? "")
                .font(OnboardingLayout.noteFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: OnboardingLayout.keyCardWidth)
        }
    }

    // MARK: Changing it

    private var recorder: some View {
        VStack(spacing: EmberDesign.Spacing.s) {
            ERow(
                OnboardingStrings.text(model.caps.isEmpty ? "welcome.shortcut.choose" : "welcome.shortcut.change"),
                help: OnboardingStrings.text("welcome.shortcut.change.help")
            ) {
                ShortcutRecorderField(model: model.field)
            }
            .padding(.vertical, EmberDesign.Spacing.m)
            .padding(.leading, EmberDesign.Card.padding)
            .padding(.trailing, EmberDesign.Spacing.s)
            .welcomeCard()
            // A one-line slot is always kept, so a warning moves nothing above it.
            if let warning = model.field.displayedWarning {
                EInlineMessage(warning.text, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                EInlineMessage(" ", tone: .warning)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: OnboardingLayout.keyCardWidth)
    }

    /// The caps dip and spring back each time the shortcut is pressed; under Reduce Motion only
    /// the success line changes.
    private func press() {
        guard !reduceMotion else { return }
        withAnimation(EmberDesign.Motion.menuIn) { isPressed = true }
        Task {
            try? await Task.sleep(for: OnboardingLayout.heroCapPressDuration)
            withAnimation(EmberDesign.Motion.dialog(reduceMotion: false)) { isPressed = false }
        }
    }
}
