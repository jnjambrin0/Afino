import PIDesign
import PIProviders
import SwiftUI

/// One provider's API key: its name and state, the field, its buttons and a one-line message.
/// Settings › Engine shows one per provider; the welcome's key step shows the chosen provider's.
///
/// States (`KeyEntryModel.Phase`): Empty (placeholder, Paste) · Editing (secure entry, Paste,
/// Save, and Cancel while replacing a saved key) · Checking (masked, spinner, the buttons
/// disabled) · Valid (masked, green badge, Paste, Check, Remove) · Invalid (red ring, message,
/// Paste, Check, Remove) · Unverified (orange "Not checked", Check, Remove). A saved key is only
/// ever shown masked.
struct EKeyField: View {
    let model: KeyEntryModel
    /// Remove was pressed; the owner confirms, then calls `model.remove()`.
    var onRemove: () -> Void = {}
    var openURL: (URL) -> Void = { _ in }

    @FocusState private var isFieldFocused: Bool

    private var provider: ProviderID { model.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            header
            HStack(spacing: EmberDesign.Spacing.s) {
                field
                buttons
            }
            if let message = model.displayedMessage {
                EInlineMessage(message.text, tone: tone(for: message))
            }
        }
        .animation(nil, value: model.phase)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            Text(verbatim: provider.displayName)
                .font(SettingsLayout.providerNameFont)
            // The badge crossfades between states in place (its width changes only the space
            // before "Get a key").
            ZStack(alignment: .leading) {
                if let badge {
                    EKeyStatusBadge(badge.status, title: badge.title)
                        .id(badge.status)
                        .transition(.opacity)
                }
            }
            .animation(EmberDesign.Motion.stateCrossfade, value: badge?.status)
            Spacer(minLength: EmberDesign.Spacing.s)
            Button(SettingsStrings.text("settings.key.getKey")) {
                openURL(Self.consoleURL(for: provider))
            }
            .buttonStyle(.ember(.ghost, size: .small))
            .accessibilityAddTraits(.isLink)
            // VoiceOver reads the words, not the arrow glyph.
            .accessibilityLabel(Text(verbatim: Self.spokenLinkTitle(SettingsStrings.text("settings.key.getKey"))))
        }
    }

    private var badge: (status: EKeyStatus, title: String)? {
        switch model.phase {
        case .empty, .editing:
            model.masked == nil ? (.notSet, SettingsStrings.text("settings.key.status.missing")) : nil
        case .checking: (.checking, SettingsStrings.text("settings.key.status.checking"))
        case .valid: (.valid, SettingsStrings.text("settings.key.status.valid"))
        case .invalid: (.invalid, SettingsStrings.text("settings.key.status.invalid"))
        case .unverified: (.unverified, SettingsStrings.text("settings.key.status.unverified"))
        }
    }

    // MARK: Field

    @ViewBuilder
    private var field: some View {
        switch model.phase {
        case .empty, .editing:
            SecureField(
                text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                prompt: Text(verbatim: SettingsStrings.text("settings.key.placeholder", provider.displayName))
                    .foregroundStyle(EmberDesign.Status.placeholder)
            ) {
                Text(verbatim: SettingsStrings.text("settings.key.accessibility", provider.displayName))
            }
            .font(.body)
            .focused($isFieldFocused)
            .onSubmit { Task { await model.save() } }
            .onKeyPress(.escape) {
                guard model.canCancel else { return .ignored }
                model.cancelReplacing()
                return .handled
            }
            .emberFieldChrome(isFocused: isFieldFocused, isInvalid: model.isInvalid)
            .onAppear {
                if model.isReplacing { isFieldFocused = true }
            }
        case .checking, .valid, .invalid, .unverified:
            Button(action: model.beginReplacing) {
                HStack(spacing: EmberDesign.Spacing.s) {
                    Text(verbatim: model.masked ?? "")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.phase == .checking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text(verbatim: SettingsStrings.text("settings.key.status.checking")))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .emberFieldChrome(isFocused: false, isInvalid: model.isInvalid)
                .contentShape(.interaction, Rectangle())
                .contentShape(.focusEffect, RoundedRectangle(cornerRadius: EmberDesign.Radius.field, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.phase == .checking)
            .accessibilityLabel(Text(verbatim: SettingsStrings.text("settings.key.accessibility", provider.displayName)))
            .accessibilityValue(Text(verbatim: model.masked ?? ""))
            .accessibilityHint(Text(verbatim: SettingsStrings.text("settings.key.replace.hint")))
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        let isChecking = model.phase == .checking
        switch model.phase {
        case .empty, .editing:
            pasteButton
            if model.canCancel {
                Button(SettingsStrings.text("settings.key.cancel"), action: model.cancelReplacing)
                    .buttonStyle(.ember(.secondary))
            }
            if model.phase == .editing {
                Button(SettingsStrings.text("settings.key.save")) {
                    Task { await model.save() }
                }
                .buttonStyle(.ember(.primary))
                .disabled(!model.canSave)
            }
        case .checking, .valid, .invalid, .unverified:
            Group {
                if model.phase != .unverified {
                    pasteButton
                }
                Button(SettingsStrings.text("settings.key.check")) {
                    Task { await model.check() }
                }
                .buttonStyle(.ember(.secondary))
                // Bordered like its neighbours: a bare word beside filled buttons reads as
                // disabled. The confirmation dialog carries the destructive styling.
                Button(SettingsStrings.text("settings.key.remove"), action: onRemove)
                    .buttonStyle(.ember(.secondary))
            }
            .disabled(isChecking)
        }
    }

    private var pasteButton: some View {
        Button {
            Task { await model.paste() }
        } label: {
            EButtonLabel(SettingsStrings.text("settings.key.paste"), systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.ember(.secondary))
        .disabled(model.phase == .checking)
    }

    private func tone(for message: KeyEntryModel.Message) -> EInlineMessage.Tone {
        switch message.tone {
        case .error: .error
        case .warning: .warning
        case .note: .note
        }
    }

    /// A link title without its trailing "↗".
    static func spokenLinkTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "↗", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Where each provider hands out API keys.
    static func consoleURL(for provider: ProviderID) -> URL {
        switch provider {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        }
    }
}
