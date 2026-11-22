import PICore
import PIDesign
import SwiftUI

/// The 44 pt footer: "For" and the target chip on the leading edge, the refine field (or a note
/// about the draft's length) in the middle, clickable hints and the single accent button on the
/// trailing edge. The accent button always names what Return will do.
struct PanelFooterView: View {
    let controller: PanelController

    var body: some View {
        // A rate limit's wait disables the recovery second by second; otherwise nothing ticks.
        if controller.problemHasCountdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(spec: controller.footerSpec(at: context.date))
            }
        } else {
            content(spec: controller.footerSpec(at: .now))
        }
    }

    private func content(spec: PanelFooterSpec) -> some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            if spec.showsTarget {
                targetChip(spec: spec)
            }

            if spec.showsRefineField {
                HostedView(view: controller.refineField)
                    .frame(minWidth: PanelLayout.refineFieldMinWidth, maxWidth: .infinity)
                    .frame(height: EmberDesign.Control.fieldHeight)
                    .padding(.leading, EmberDesign.Spacing.xs)
                    .accessibilityLabel(Text(verbatim: PanelStrings.refinePlaceholder))
            } else if let message = spec.message {
                FooterMessageView(message: message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: EmberDesign.Spacing.s)
            }

            HStack(spacing: EmberDesign.Spacing.xxs) {
                ForEach(spec.hints, id: \.self) { hint in
                    PanelHintButton(hint: hint) { controller.perform(hint.command) }
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                            if hint.command == .toggleActions { controller.model.actionsHintFrame = frame }
                        }
                }
            }
            .fixedSize()

            if spec.showsStop {
                Button { controller.perform(.escape) } label: {
                    EButtonLabel(PanelStrings.stop, chord: spec.stopChord)
                }
                .buttonStyle(.ember(.secondary))
                .accessibilityIdentifier(PanelAccessibilityID.stopButton)
            }

            if let primary = spec.primary {
                Button { controller.perform(.primary) } label: {
                    EButtonLabel(Self.title(of: primary), chord: spec.primaryChord)
                }
                .buttonStyle(.ember(.primary))
                .disabled(!spec.isPrimaryEnabled)
                // The accent button always says in full what Return does; the refine field gives way.
                .fixedSize()
                .layoutPriority(1)
                .accessibilityIdentifier(PanelAccessibilityID.primaryButton)
            }
        }
        .padding(.leading, PanelLayout.textLeadingInset)
        .padding(.trailing, EmberDesign.Panel.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PanelAccessibilityID.footer)
    }

    @ViewBuilder
    private func targetChip(spec: PanelFooterSpec) -> some View {
        let pack = controller.session.target
        let name = PanelMenus.displayName(of: pack)
        HStack(spacing: EmberDesign.Spacing.s) {
            Text(verbatim: PanelStrings.targetPrefix)
                .font(EmberDesign.Typography.chipName)
                .foregroundStyle(.secondary)
                .opacity(spec.isTargetDimmed ? EmberDesign.Control.dimmedOpacity : 1)
                .accessibilityHidden(true)
            ETargetChip(
                name,
                monogram: HistoryRowFormatter.monogram(for: pack),
                caps: spec.targetChord.map(ShortcutGlyphFormatter.caps(for:)) ?? [],
                isDimmed: spec.isTargetDimmed,
                accessibilityLabel: PanelStrings.targetAccessibility(name),
                accessibilityHint: PanelStrings.targetAccessibilityHint
            ) {
                controller.toggleMenu(.target)
            }
            .allowsHitTesting(spec.isTargetInteractive)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                controller.model.targetChipFrame = frame
            }
            .accessibilityIdentifier(PanelAccessibilityID.targetChip)
        }
        .fixedSize()
    }

    static func title(of action: PanelPrimaryAction) -> String {
        switch action {
        case .improve: PanelStrings.improve
        case .refine: PanelStrings.refine
        case .rewrite(let name): PanelStrings.rewriteFor(name)
        case .copyAndClose: PanelStrings.copyAndClose
        case .recovery(.tryAgain): PanelStrings.tryAgain
        case .recovery(.openSettings): PanelStrings.openSettings
        case .recovery(.edit): PanelStrings.edit
        case .saveKey: PanelStrings.saveKey
        }
    }
}

/// A clickable hint: the caps from the key map and, for most, a word ("⌘Y History").
struct PanelHintButton: View {
    let hint: PanelHint
    let action: () -> Void

    var body: some View {
        let title = Self.title(of: hint.label)
        Button(action: action) {
            HStack(spacing: EmberDesign.KeyCap.labelSpacing) {
                EKeyCapGroup(hint.chord)
                if let title {
                    Text(verbatim: title)
                        .font(EmberDesign.Typography.hint)
                }
            }
        }
        .buttonStyle(.ember(.ghost, size: .small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title ?? Self.spokenName(of: hint.command)), \(ShortcutGlyphFormatter.string(for: hint.chord))"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(PanelAccessibilityID.hint(hint.command))
    }

    static func title(of label: PanelHintLabel) -> String? {
        switch label {
        case .none: nil
        case .history: PanelStrings.history
        case .newLine: PanelStrings.newLine
        case .copy: PanelStrings.copy
        case .edit: PanelStrings.edit
        case .open: PanelStrings.open
        case .delete: PanelStrings.delete
        case .back: PanelStrings.back
        }
    }

    /// What VoiceOver calls a hint that shows only caps.
    static func spokenName(of command: PanelCommand) -> String {
        switch command {
        case .toggleActions: PanelStrings.actions
        case .toggleHistory: PanelStrings.history
        default: PanelStrings.actions
        }
    }
}

/// The quiet note about a long draft, in the footer's middle slot.
struct FooterMessageView: View {
    let message: PanelFooterMessage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.xs) {
            Image(systemName: message == .tooLong ? "exclamationmark.triangle.fill" : "clock")
                .foregroundStyle(message == .tooLong ? EmberDesign.Status.caution : EmberDesign.Status.neutral)
                .accessibilityHidden(true)
            Text(verbatim: message == .tooLong ? PanelStrings.tooLong : PanelStrings.longDraft)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(EmberDesign.Typography.hint)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(PanelAccessibilityID.footerMessage)
    }
}
