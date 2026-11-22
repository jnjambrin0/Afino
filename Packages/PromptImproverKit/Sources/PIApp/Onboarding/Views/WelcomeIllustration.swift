import PIDesign
import SwiftUI

/// What the illustrated panel shows for a target.
struct WelcomeIllustrationTarget: Equatable {
    let name: String
    let monogram: EMonogram
}

/// The first step's picture: the panel, drawn with its own tokens and kit, turning a rough line
/// into a clean prompt. It plays once — the accent caret breathes ("thinking"), the prompt streams
/// in a word at a time, then "Copied" — and is still under Reduce Motion (it shows the end).
/// Decorative: hidden from accessibility, nothing in it can be clicked.
struct WelcomeIllustration: View {
    let target: WelcomeIllustrationTarget
    /// Already played this showing: show the end straight away.
    let hasPlayed: Bool
    let onPlayed: () -> Void

    private enum Phase: Equatable {
        case thinking
        case writing(words: Int)
        case copied
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.thinking

    private var draft: String { OnboardingStrings.text("welcome.demo.draft") }
    private var words: [String] {
        OnboardingStrings.text("welcome.demo.result").split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EmberDesign.Radius.window, style: .continuous)
        VStack(spacing: 0) {
            header
            well
                .padding(.horizontal, EmberDesign.Panel.contentInset)
            footer
        }
        .frame(width: OnboardingLayout.illustrationWidth)
        .glassEffect(.regular, in: shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
    }

    // MARK: Parts (the panel's result state: origin row, well, footer)

    private var header: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Image(systemName: "quote.opening")
                .font(EmberDesign.Typography.hint)
                .foregroundStyle(.tertiary)
            Text(verbatim: draft)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: EmberDesign.Spacing.m)
            status
        }
        .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding + EmberDesign.Panel.contentInset)
        .frame(height: EmberDesign.Panel.headerHeight)
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .thinking:
            Text(verbatim: OnboardingStrings.text("welcome.demo.thinking"))
                .font(EmberDesign.Typography.hint)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        case .writing:
            Text(verbatim: OnboardingStrings.text("welcome.demo.writing"))
                .font(EmberDesign.Typography.hint)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        case .copied:
            HStack(spacing: EmberDesign.Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(EmberDesign.Typography.hint.weight(.bold))
                    .foregroundStyle(EmberDesign.Brand.accentMark)
                Text(verbatim: OnboardingStrings.text("welcome.demo.copied"))
                    .font(EmberDesign.Typography.hint)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private var well: some View {
        EWell {
            // The whole prompt is always laid out, the words not yet arrived drawn clear, so the
            // well never changes height while the text streams in.
            streamedText
                .font(EmberDesign.Typography.resultBody)
                .lineSpacing(EmberDesign.Typography.resultLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if phase == .thinking {
                        EAccentCaret(mode: reduceMotion ? .solid : .breathing, height: EmberDesign.Panel.inputLineHeight)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding)
                .padding(.vertical, EmberDesign.Panel.wellVerticalPadding)
        }
    }

    private var streamedText: Text {
        let shown: Int
        switch phase {
        case .thinking: shown = 0
        case .writing(let count): shown = count
        case .copied: shown = words.count
        }
        let visible = words.prefix(shown).joined(separator: " ")
        let hidden = words.dropFirst(shown).joined(separator: " ")
        let gap = shown > 0 && shown < words.count ? " " : ""
        return Text("\(Text(verbatim: visible).foregroundStyle(.primary))\(Text(verbatim: gap + hidden).foregroundStyle(.clear))")
    }

    private var footer: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Text(verbatim: OnboardingStrings.text("welcome.demo.for"))
                .font(EmberDesign.Typography.chipName)
                .foregroundStyle(.secondary)
            // The target chip's look; not the chip itself, which is a button.
            HStack(spacing: EmberDesign.Chip.itemSpacing) {
                EMonogramTile(target.monogram)
                Text(verbatim: target.name)
                    .font(EmberDesign.Typography.chipName)
            }
            .padding(.leading, EmberDesign.Chip.leadingInset)
            .padding(.trailing, EmberDesign.Chip.trailingPadding)
            .frame(minHeight: EmberDesign.Chip.targetHeight)
            .background(Capsule(style: .continuous).fill(EmberDesign.Materials.chipFill(isHovered: false)))
            Spacer(minLength: EmberDesign.Spacing.s)
            EKeyCapGroup(KeyChord(.char("k"), .command))
                .opacity(EmberDesign.Control.dimmedOpacity)
            // Not the accent fill: on this step the only accent button is Continue.
            EButtonLabel(OnboardingStrings.text("welcome.demo.copyClose"), chord: KeyChord(.returnKey))
                .font(EmberDesign.Typography.button)
                .padding(.horizontal, EmberDesign.Control.horizontalPadding)
                .frame(minHeight: EmberDesign.Control.height)
                .background(
                    RoundedRectangle(cornerRadius: EmberDesign.Radius.control, style: .continuous)
                        .fill(.fill.tertiary)
                )
        }
        .padding(.leading, EmberDesign.Panel.wellHorizontalPadding + EmberDesign.Panel.contentInset)
        .padding(.trailing, EmberDesign.Panel.contentInset)
        .frame(height: EmberDesign.Panel.footerHeight)
    }

    // MARK: Playing

    private func play() async {
        guard !hasPlayed, !reduceMotion else {
            phase = .copied
            return
        }
        phase = .thinking
        try? await Task.sleep(for: OnboardingLayout.illustrationThinking)
        guard !Task.isCancelled else { return }
        // The caret fades as the first word arrives; after that nothing animates per word.
        withAnimation(EmberDesign.Motion.contentCrossfade) { phase = .writing(words: 1) }
        for count in 1...words.count {
            if count > 1 { phase = .writing(words: count) }
            try? await Task.sleep(for: OnboardingLayout.illustrationWordInterval)
            guard !Task.isCancelled else { return }
        }
        try? await Task.sleep(for: OnboardingLayout.illustrationSettle)
        guard !Task.isCancelled else { return }
        withAnimation(EmberDesign.Motion.contentCrossfade) { phase = .copied }
        onPlayed()
    }
}
