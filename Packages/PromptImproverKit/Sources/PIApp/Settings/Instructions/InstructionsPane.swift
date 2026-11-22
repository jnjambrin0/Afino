import PICore
import PIDesign
import SwiftUI

/// Settings › Instructions: the user's standing preferences, added to every improvement.
struct InstructionsPane: View {
    let settings: SettingsModel

    @State private var isEditorFocused = false

    private var isOn: Bool { settings.customInstructionsEnabled }

    var body: some View {
        SettingsPaneContainer(SettingsPane.instructions.title) {
            SettingsSection {
                SettingsToggleRow(
                    title: SettingsStrings.text("settings.instructions.toggle.title"),
                    isOn: Binding(
                        get: { settings.customInstructionsEnabled },
                        set: { settings.customInstructionsEnabled = $0 }
                    )
                )
            }

            SettingsSection(
                SettingsStrings.text("settings.instructions.editor.section"),
                footer: SettingsStrings.text("settings.instructions.footer")
            ) {
                SettingsBlock {
                    editor
                    counter
                }
            }

            SettingsSection(
                SettingsStrings.text("settings.instructions.examples.section"),
                footer: SettingsStrings.text("settings.instructions.examples.footer")
            ) {
                SettingsBlock {
                    EFlowLayout(spacing: EmberDesign.Spacing.xs) {
                        ForEach(InstructionsText.Example.allCases, id: \.self) { example in
                            let appended = InstructionsText.appending(example.sentence, to: settings.customInstructions)
                            EActionChip(example.sentence, symbol: "plus") {
                                if let appended { settings.customInstructions = appended }
                            }
                            .disabled(appended == nil || !isOn)
                        }
                    }
                }
            }
        }
    }

    private var editor: some View {
        InstructionsEditor(
            text: Binding(
                get: { settings.customInstructions },
                set: { settings.customInstructions = InstructionsText.capped($0) }
            ),
            placeholder: SettingsStrings.text("settings.instructions.editor.placeholder"),
            accessibilityLabel: SettingsStrings.text("settings.instructions.editor.accessibility"),
            isEditable: isOn,
            isFocused: $isEditorFocused
        )
        .frame(minHeight: InstructionsEditor.height(lines: SettingsLayout.instructionsMinLines))
        .emberFieldChrome(isFocused: isEditorFocused && isOn)
    }

    private var counter: some View {
        let count = InstructionsText.count(of: settings.customInstructions)
        return HStack(spacing: EmberDesign.Badge.glyphSpacing) {
            Spacer(minLength: 0)
            // Near the limit the count gains a glyph, not only a colour.
            if count.isNearLimit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
            }
            Text(verbatim: count.text)
                .monospacedDigit()
        }
        .font(EmberDesign.Typography.fieldHelp)
        .foregroundStyle(count.isNearLimit ? AnyShapeStyle(EmberDesign.Status.caution) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: count.accessibilityText))
    }
}
