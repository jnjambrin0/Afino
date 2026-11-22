import PICore
import PIDesign
import PIProviders
import SwiftUI

/// The add-a-key card (680 × 232), in place of the composer while the chosen provider has no
/// usable key: provider chips, a secure field with Paste, the privacy line and Save Key. Pasting or
/// pressing Return checks the key with the provider at once.
struct SetupCardView: View {
    let controller: PanelController

    var body: some View {
        let model = controller.model
        let provider = controller.settings.provider
        let isChecking = model.setupStatus == .checking
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.xs) {
                Text(verbatim: PanelStrings.setupTitle)
                    .font(EmberDesign.Typography.dialogTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: PanelStrings.setupBody)
                    .font(EmberDesign.Typography.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, EmberDesign.Spacing.xl)

            EChoiceChips(
                PanelStrings.providerLabel,
                options: ProviderID.allCases,
                selection: Binding(get: { provider }, set: { controller.selectProvider($0) })
            ) { $0.displayName }
            .disabled(isChecking)
            .fixedSize()
            .padding(.top, EmberDesign.Spacing.m)
            .padding(.leading, -EmberDesign.Spacing.xxs)

            HStack(spacing: EmberDesign.Spacing.s) {
                HostedView(view: controller.keyField)
                    .frame(maxWidth: .infinity)
                    .frame(height: EmberDesign.Control.fieldHeight)
                    .emberFieldChrome(isFocused: model.isKeyFieldFocused, isInvalid: model.setupStatus == .rejected)
                    .accessibilityLabel(Text(verbatim: PanelStrings.keyFieldLabel))
                Button { controller.pasteKey() } label: {
                    EButtonLabel(PanelStrings.paste, systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.ember(.secondary))
                .disabled(isChecking)
                .accessibilityIdentifier(PanelAccessibilityID.setupPaste)
            }
            .padding(.top, EmberDesign.Spacing.s)

            SetupStatusLine(controller: controller, provider: provider)
                .padding(.top, EmberDesign.Spacing.s)

            Spacer(minLength: 0)

            HStack(spacing: EmberDesign.Spacing.s) {
                Button { controller.openKeyPage() } label: {
                    EButtonLabel(PanelStrings.getKey, systemImage: "arrow.up.right")
                }
                .buttonStyle(.ember(.ghost, size: .small))
                .padding(.leading, -EmberDesign.Control.smallHorizontalPadding)
                .accessibilityIdentifier(PanelAccessibilityID.setupGetKey)
                Spacer(minLength: EmberDesign.Spacing.s)
                Button { controller.perform(.primary) } label: {
                    EButtonLabel(PanelStrings.saveKey, chord: PanelKeyMap.chord(for: .primary, in: .setup))
                }
                .buttonStyle(.ember(.primary))
                .disabled(isChecking)
                .accessibilityIdentifier(PanelAccessibilityID.setupSave)
            }
            // The accent button sits where the footer's does, at the content inset.
            .padding(.trailing, -(PanelLayout.textLeadingInset - EmberDesign.Panel.contentInset))
            .frame(height: EmberDesign.Panel.footerHeight)
        }
        .padding(.leading, PanelLayout.textLeadingInset)
        .padding(.trailing, PanelLayout.textLeadingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PanelAccessibilityID.setupCard)
    }
}

/// Under the key field: the privacy line, or what the check said.
struct SetupStatusLine: View {
    let controller: PanelController
    let provider: ProviderID

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.xs) {
            glyph
                .accessibilityHidden(true)
            Text(verbatim: message)
                .foregroundStyle(isNeutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            if case .wrongProvider(let other) = controller.model.setupStatus {
                Button { controller.useProvider(other) } label: {
                    Text(verbatim: PanelStrings.useProvider(other.displayName))
                }
                .buttonStyle(.ember(.secondary, size: .small))
            }
        }
        .font(EmberDesign.Typography.fieldHelp)
        .frame(minHeight: EmberDesign.Control.smallHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(PanelAccessibilityID.setupStatus)
    }

    private var isNeutral: Bool {
        switch controller.model.setupStatus {
        case .idle, .checking: true
        default: false
        }
    }

    private var message: String {
        switch controller.model.setupStatus {
        case .idle: PanelStrings.keyPrivacy(provider.displayName)
        case .checking: PanelStrings.checking
        case .accepted: PanelStrings.keyWorks
        case .unverified: PanelStrings.keyUnverified
        case .rejected: PanelStrings.keyRejected
        case .wrongProvider(let other): PanelStrings.wrongProvider(other.displayName)
        case .storeFailed: PanelStrings.keyStoreFailed
        case .empty: PanelStrings.keyEmpty
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch controller.model.setupStatus {
        case .idle:
            Image(systemName: "lock.fill").foregroundStyle(.tertiary)
        case .checking:
            ProgressView().controlSize(.mini)
        case .accepted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(EmberDesign.Status.positive)
        case .unverified, .wrongProvider, .empty:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(EmberDesign.Status.caution)
        case .rejected, .storeFailed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(EmberDesign.Status.negative)
        }
    }
}
