import PIDesign
import SwiftUI

/// The shortcut recorder: a capsule field showing the shortcut as key caps, as wide as the selects
/// below it in Settings › General (the welcome's shortcut step shows it too). Clicking it records
/// (focus ring, "Type shortcut", the modifiers as they are held); Esc or a second click cancels,
/// Delete turns the shortcut off, and so does the clear button at its trailing end (like a search
/// field's).
struct ShortcutRecorderField: View {
    let model: ShortcutFieldModel

    var body: some View {
        let canClear = model.shortcut != nil && !model.isRecording
        ZStack(alignment: .trailing) {
            Button(action: model.toggleRecording) {
                content
                    // The caps stay centred in the whole field; the clear button sits over the
                    // trailing inset, which the caps never reach.
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, EmberDesign.Control.iconButtonSize - EmberDesign.Control.fieldHorizontalPadding)
            }
            .buttonStyle(RecorderButtonStyle(isRecording: model.isRecording))
            .accessibilityLabel(Text(verbatim: SettingsStrings.text("settings.shortcut.record.accessibility")))
            .accessibilityValue(Text(verbatim: model.isRecording
                ? SettingsStrings.text("settings.shortcut.recording")
                : model.spokenShortcut))

            // Always laid out, so nothing shifts when it comes and goes.
            Button(SettingsStrings.text("settings.shortcut.clear"), systemImage: "xmark.circle.fill", action: model.clear)
                .labelStyle(.iconOnly)
                .buttonStyle(.emberIcon)
                .help(Text(verbatim: SettingsStrings.text("settings.shortcut.clear")))
                .opacity(canClear ? 1 : 0)
                .disabled(!canClear)
                .accessibilityHidden(!canClear)
        }
        .frame(width: SettingsLayout.recorderWidth)
    }

    @ViewBuilder
    private var content: some View {
        let caps = model.caps
        if !caps.isEmpty {
            EKeyCapGroup(caps: caps)
        } else if model.isRecording {
            Text(verbatim: SettingsStrings.text("settings.shortcut.recording"))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(verbatim: SettingsStrings.text("settings.shortcut.none"))
                .font(.body)
                .foregroundStyle(EmberDesign.Status.placeholder)
                .lineLimit(1)
        }
    }
}

/// The recorder's capsule field; the keyboard focus ring follows the capsule.
private struct RecorderButtonStyle: ButtonStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .emberFieldChrome(isFocused: isRecording, shape: .capsule)
            .contentShape(.interaction, shape)
            .contentShape(.focusEffect, shape)
    }
}
