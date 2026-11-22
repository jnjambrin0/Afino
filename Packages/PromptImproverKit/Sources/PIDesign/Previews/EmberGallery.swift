#if DEBUG
import AppKit
import SwiftUI

private enum GalleryTarget: String, CaseIterable, Hashable {
    case claude, gpt, gemini, generic

    var title: String {
        switch self {
        case .claude: "Claude"
        case .gpt: "GPT"
        case .gemini: "Gemini"
        case .generic: "Any model"
        }
    }

    var monogram: EMonogram {
        switch self {
        case .claude: .letters("Cl")
        case .gpt: .letters("Gp")
        case .gemini: .letters("Ge")
        case .generic: .symbol("circle.dotted")
        }
    }
}

private enum GalleryPreset: String, CaseIterable, Hashable {
    case quality, balanced, fast, custom

    var title: String { rawValue.capitalized }
}

/// Every Ember component, with mock-ups of the panel's compose and result states, over a busy
/// backdrop so the Liquid Glass has something to refract. Open it in Xcode's canvas (the light
/// and dark previews below) or render it to PNGs with
/// `PI_GALLERY_SNAPSHOTS=<folder> swift test --filter GallerySnapshotTests` to check a kit
/// change by eye. Debug builds only: none of this ships.
struct EmberGallery: View {
    @State private var draft = ""
    @State private var key = "sk-ant-…"
    @State private var theme = "System"
    @State private var historyOn = true
    @State private var target = GalleryTarget.claude
    @State private var preset = GalleryPreset.balanced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxl) {
                composePanel
                resultPanel
                section("Buttons") { buttons }
                section("Controls") { controls }
                section("Chips, tiles, caps, badges") { chips }
                section("Surfaces") { surfaces }
                section("Menu and dialog") { menuAndDialog }
            }
            .padding(EmberDesign.Spacing.xxl)
        }
        .frame(width: EmberDesign.Panel.width + EmberDesign.Spacing.xxl * 2, height: EmberDesign.Settings.windowSize.height * 2)
        .background(GalleryBackdrop())
        .emberFloatingLayer()
    }

    // MARK: Panel mock-ups

    /// Compose: 680 × 96, input on the glass, footer with the target chip.
    private var composePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: EmberDesign.Spacing.xxs) {
                EAccentCaret(mode: .solid, height: EmberDesign.Panel.inputLineHeight)
                Text(verbatim: "Describe what you want or paste a draft…")
                    .font(EmberDesign.Typography.input)
                    .foregroundStyle(EmberDesign.Status.placeholder)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding)
            .frame(height: EmberDesign.Panel.inputMinHeight)
            footer(primary: "Improve")
        }
        .frame(width: EmberDesign.Panel.width, height: EmberDesign.Panel.composeHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: EmberDesign.Radius.window, style: .continuous))
    }

    /// Result: header, well (thinking caret), footer.
    private var resultPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: EmberDesign.Spacing.s) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(.secondary)
                Text(verbatim: "write a prompt that makes a snake game…")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: EmberDesign.Spacing.s)
                Text(verbatim: "Thinking… 2 s")
                    .font(EmberDesign.Typography.hint)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding)
            .frame(height: EmberDesign.Panel.headerHeight)

            EWell {
                HStack(alignment: .top, spacing: EmberDesign.Spacing.xxs) {
                    Text(verbatim: "You are a senior front-end game developer. Build a complete snake game")
                        .font(EmberDesign.Typography.resultBody)
                        .lineSpacing(EmberDesign.Typography.resultLineSpacing)
                    EAccentCaret(mode: .breathing, height: EmberDesign.Panel.inputLineHeight)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, EmberDesign.Panel.wellHorizontalPadding)
                .padding(.vertical, EmberDesign.Panel.wellVerticalPadding)
                .frame(minHeight: EmberDesign.Panel.wellMinHeight, alignment: .topLeading)
            }
            .padding(.horizontal, EmberDesign.Panel.contentInset)

            footer(primary: "Copy and close")
        }
        .frame(width: EmberDesign.Panel.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: EmberDesign.Radius.window, style: .continuous))
    }

    private func footer(primary: String) -> some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Text(verbatim: "For")
                .font(EmberDesign.Typography.hint)
                .foregroundStyle(.secondary)
            ETargetChip(
                target.title,
                monogram: target.monogram,
                chord: KeyChord(.tab),
                accessibilityLabel: "Target: \(target.title)"
            ) {
                let all = GalleryTarget.allCases
                target = all[((all.firstIndex(of: target) ?? 0) + 1) % all.count]
            }
            Spacer(minLength: EmberDesign.Spacing.s)
            Button("History", systemImage: "clock") {}
                .labelStyle(.iconOnly)
                .buttonStyle(.emberIcon)
            Button {} label: {
                EButtonLabel("Actions", chord: KeyChord(.char("k"), .command))
            }
            .buttonStyle(.ember(.ghost, size: .small))
            Button {} label: {
                EButtonLabel(primary, chord: KeyChord(.returnKey))
            }
            .buttonStyle(.ember(.primary))
        }
        .padding(.horizontal, EmberDesign.Panel.contentInset)
        .frame(height: EmberDesign.Panel.footerHeight)
    }

    // MARK: Sections

    private var buttons: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            HStack(spacing: EmberDesign.Spacing.s) {
                Button {} label: { EButtonLabel("Improve", chord: KeyChord(.returnKey)) }
                    .buttonStyle(.ember(.primary))
                Button("Secondary") {}.buttonStyle(.ember(.secondary))
                Button("Ghost") {}.buttonStyle(.ember(.ghost))
                Button("Remove key") {}.buttonStyle(.ember(.destructive))
                Button("Disabled") {}.buttonStyle(.ember(.primary)).disabled(true)
            }
            HStack(spacing: EmberDesign.Spacing.s) {
                Button {} label: { EButtonLabel("Paste", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.ember(.secondary, size: .small))
                Button("Check") {}.buttonStyle(.ember(.ghost, size: .small))
                Button("Copy", systemImage: "doc.on.doc") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(.emberIcon)
                Button("Pinned", systemImage: "pin.fill") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(.emberIcon(isActive: true))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            EField("Paste your Anthropic API key", text: $key)
            EField("Invalid field", text: $draft, isInvalid: true)
            EChoiceChips("Theme", options: ["System", "Light", "Dark"], selection: $theme)
            EChoiceChips(
                "Provider",
                options: ["Anthropic", "OpenAI"],
                selection: .constant("Anthropic"),
                isAvailable: { $0 == "Anthropic" },
                unavailableHelp: { _ in "Add an OpenAI key first" }
            ) { $0 }
            HStack(spacing: EmberDesign.Spacing.xs) {
                EActionChip("Use XML tags", symbol: "plus") {}
                EActionChip("Keep it under 200 words", symbol: "plus") {}
                    .disabled(true)
            }
            HStack(spacing: EmberDesign.Spacing.m) {
                Toggle("Keep history", isOn: $historyOn)
                    .toggleStyle(.ember)
                    .fixedSize()
                Toggle("Off", isOn: .constant(false))
                    .toggleStyle(.ember)
                    .labelsHidden()
                Toggle("Disabled", isOn: .constant(true))
                    .toggleStyle(.ember)
                    .labelsHidden()
                    .disabled(true)
            }
            HStack(spacing: EmberDesign.Spacing.m) {
                ESelect("Preset", options: GalleryPreset.allCases, selection: $preset) { $0.title }
                ESelect(
                    "Default target",
                    options: GalleryTarget.allCases,
                    selection: $target,
                    minWidth: EmberDesign.Card.selectMenuMinWidth,
                    monogram: { $0.monogram },
                    title: { $0.title }
                )
            }
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            HStack(spacing: EmberDesign.Spacing.s) {
                ForEach(GalleryTarget.allCases, id: \.self) { EMonogramTile($0.monogram) }
                ETargetChip("Gemini", monogram: .letters("Ge"), accessibilityLabel: "Target: Gemini") {}
                ETargetChip("Any model", monogram: .symbol("circle.dotted"), isDimmed: true, accessibilityLabel: "Target: Any model") {}
            }
            HStack(spacing: EmberDesign.Spacing.m) {
                EKeyCapGroup(KeyChord(.char("c"), [.shift, .command]))
                EKeyCapGroup(caps: ["⌃", "⌥", "P"])
                EKeyCapGroup(KeyChord(.escape))
            }
            HStack(spacing: EmberDesign.Spacing.s) {
                EKeyStatusBadge(.notSet, title: "Not set")
                EKeyStatusBadge(.checking, title: "Checking…")
                EKeyStatusBadge(.valid, title: "Valid")
                EKeyStatusBadge(.invalid, title: "Not valid")
                EKeyStatusBadge(.unverified, title: "Not checked")
            }
        }
    }

    private var surfaces: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            ESectionHeader("Engine", subtitle: "Which API rewrites your prompts.")
            ECard {
                ERow("Provider", help: "Your key is stored in your Mac's Keychain.") {
                    EKeyStatusBadge(.valid, title: "Valid")
                }
                ERow("Keep history") {
                    Toggle("Keep history", isOn: $historyOn)
                        .toggleStyle(.ember)
                        .labelsHidden()
                }
            }
            EInlineMessage("The provider is overloaded. Try again in a moment.", tone: .error)
            EInlineMessage("Partial result. It has not been copied.", tone: .warning)
            EInlineMessage("Only sent to Anthropic.", tone: .note)
            EToast("Prompt deleted", symbol: "trash", actionTitle: "Undo", actionChord: KeyChord(.char("z"), .command))
        }
    }

    private var menuAndDialog: some View {
        HStack(alignment: .top, spacing: EmberDesign.Spacing.l) {
            EMenuCard(
                items: [
                    .header(id: "h-target", title: "Target", section: 0),
                    EMenuItem(id: "cl", title: "Claude", monogram: .letters("Cl"), shortcut: KeyChord(.char("1"), .command), isChecked: true),
                    EMenuItem(id: "gp", title: "GPT", monogram: .letters("Gp"), shortcut: KeyChord(.char("2"), .command)),
                    EMenuItem(id: "shorter", title: "Shorter", symbol: "text.badge.minus", section: 1),
                    EMenuItem(id: "examples", title: "Add examples", symbol: "text.badge.plus", isEnabled: false, hint: "Finish the run first", section: 1),
                    EMenuItem(id: "delete", title: "Delete from history", symbol: "trash", isDestructive: true, section: 2),
                ],
                highlightedID: "gp",
                onHover: { _ in },
                onSelect: { _ in }
            )
            EDialog(
                "Remove the OpenAI key?",
                message: "Afino can't use OpenAI until you add a key again.",
                symbol: "key",
                actions: [
                    EDialogAction("Cancel", isCancel: true) {},
                    EDialogAction("Remove", kind: .destructive, isDefault: true) {},
                ]
            )
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            ESectionHeader(title)
            content()
        }
        .padding(EmberDesign.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: EmberDesign.Radius.large, style: .continuous))
    }
}

/// A busy backdrop (flat system colours, no gradients) so the glass has
/// something to refract.
private struct GalleryBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Circle()
                    .fill(Color(nsColor: .systemTeal))
                    .frame(width: proxy.size.width * 0.6)
                    .position(x: proxy.size.width * 0.2, y: proxy.size.height * 0.15)
                Circle()
                    .fill(Color(nsColor: .systemPink))
                    .frame(width: proxy.size.width * 0.5)
                    .position(x: proxy.size.width * 0.9, y: proxy.size.height * 0.45)
                Circle()
                    .fill(Color(nsColor: .systemIndigo))
                    .frame(width: proxy.size.width * 0.7)
                    .position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.85)
            }
        }
    }
}

#Preview("Ember – Light") {
    EmberGallery()
        .preferredColorScheme(.light)
}

#Preview("Ember – Dark") {
    EmberGallery()
        .preferredColorScheme(.dark)
}
#endif
