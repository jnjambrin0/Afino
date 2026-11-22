import PIDesign
import PIProviders
import SwiftUI

/// Everything the welcome window's content needs.
struct WelcomeContext {
    let flow: WelcomeFlow
    let keyStep: WelcomeKeyStepModel
    let shortcutStep: WelcomeShortcutStepModel
    let guide: [WelcomeKeyGroup]
    let illustrationTarget: WelcomeIllustrationTarget
    let openURL: (URL) -> Void
}

/// The welcome window's content: the Skip link, the step (one size for all of them; steps slide
/// in from the side they come from, or fade under Reduce Motion), and the footer — Back, where
/// the user is, and the step's one accent button, which is what Return does.
struct WelcomeRootView: View {
    let context: WelcomeContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flow: WelcomeFlow { context.flow }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                step
                    .id(flow.step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: OnboardingLayout.windowSize.width, height: OnboardingLayout.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(EmberDesign.Motion.contentCrossfade, value: flow.step)
        .background { escapeKey }
        .emberFloatingLayer()
        .emberDialog(isPresented: context.keyStep.pendingRemoval != nil) { removalDialog }
    }

    // MARK: Step

    @ViewBuilder
    private var step: some View {
        switch flow.step {
        case .welcome:
            WelcomeIntroStepView(flow: flow, target: context.illustrationTarget)
        case .apiKey:
            WelcomeKeyStepView(model: context.keyStep, openURL: context.openURL)
        case .shortcut:
            WelcomeShortcutStepView(flow: flow, model: context.shortcutStep)
        case .keys:
            WelcomeKeysStepView(groups: context.guide)
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let slide = flow.direction == .forward ? OnboardingLayout.stepSlide : -OnboardingLayout.stepSlide
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: slide)),
            removal: .opacity.combined(with: .offset(x: -slide))
        )
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(OnboardingStrings.text("welcome.skip"), action: flow.skip)
                .buttonStyle(.ember(.ghost, size: .small))
                .opacity(flow.isLastStep ? 0 : 1)
                .disabled(flow.isLastStep)
                .accessibilityHidden(flow.isLastStep)
                .accessibilityHint(Text(verbatim: OnboardingStrings.text("welcome.skip.hint")))
        }
        // Skip's word lines up with the content and the footer's buttons.
        .padding(.horizontal, OnboardingLayout.horizontalPadding - EmberDesign.Control.smallHorizontalPadding)
        .frame(height: OnboardingLayout.topBarHeight)
    }

    private var footer: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Button(OnboardingStrings.text("welcome.back"), action: flow.back)
                .buttonStyle(.ember(.ghost))
                .opacity(flow.isFirstStep ? 0 : 1)
                .disabled(flow.isFirstStep)
                .accessibilityHidden(flow.isFirstStep)
            Spacer(minLength: EmberDesign.Spacing.l)
            if flow.step == .apiKey, context.keyStep.offersAddLater {
                Button(OnboardingStrings.text("welcome.key.later"), action: flow.advance)
                    .buttonStyle(.ember(.ghost))
                    .accessibilityHint(Text(verbatim: OnboardingStrings.text("welcome.key.later.note")))
            }
            primaryButton
        }
        .overlay { WelcomeProgress(step: flow.step) }
        .padding(.horizontal, OnboardingLayout.horizontalPadding - EmberDesign.Control.horizontalPadding)
        .frame(height: OnboardingLayout.footerHeight)
    }

    /// The step's one accent button. When it cannot be pressed it is drawn quietly, so the accent
    /// is never on a button Return would not press.
    private var primaryButton: some View {
        let isEnabled = flow.step.isPrimaryEnabled(
            keyStepCanContinue: context.keyStep.canContinue,
            isRecordingShortcut: context.shortcutStep.isRecording
        ) && context.keyStep.pendingRemoval == nil
        let title = OnboardingStrings.text(flow.isLastStep ? "welcome.start" : "welcome.continue")
        return Button(action: flow.advance) {
            EButtonLabel(title, chord: KeyChord(.returnKey))
        }
        .buttonStyle(.ember(isEnabled ? .primary : .secondary))
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
    }

    /// Esc leaves the welcome from any step, as Skip does — except while Esc has a job closer by:
    /// cancelling the replacement of a stored key, or the Remove dialog (the recorder takes Esc
    /// before the window sees it).
    private var escapeKey: some View {
        let isEnabled = context.keyStep.pendingRemoval == nil && !context.keyStep.entry.isReplacing
        return Button(OnboardingStrings.text("welcome.skip"), action: flow.skip)
            .keyboardShortcut(.cancelAction)
            .disabled(!isEnabled)
            .opacity(0)
            .allowsHitTesting(false)
            .focusable(false)
            .accessibilityHidden(true)
    }

    private var removalDialog: EDialog {
        let provider = context.keyStep.pendingRemoval?.displayName ?? ""
        return EDialog(
            OnboardingStrings.text("welcome.key.remove.title", provider),
            message: OnboardingStrings.text("welcome.key.remove.message", provider),
            symbol: "key",
            actions: [
                EDialogAction(OnboardingStrings.text("welcome.key.remove.cancel"), isCancel: true) {
                    context.keyStep.pendingRemoval = nil
                },
                EDialogAction(OnboardingStrings.text("welcome.key.remove.confirm"), kind: .destructive, isDefault: true) {
                    context.keyStep.confirmRemoval()
                },
            ]
        )
    }
}

/// Where the user is: one mark per step, the current one a short bar.
struct WelcomeProgress: View {
    let step: WelcomeStep

    var body: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            ForEach(WelcomeStep.allCases, id: \.self) { mark in
                Capsule(style: .continuous)
                    .fill(mark == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(
                        width: mark == step ? OnboardingLayout.progressCurrentWidth : OnboardingLayout.progressDotSize,
                        height: OnboardingLayout.progressDotSize
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: step.progress))
    }
}
