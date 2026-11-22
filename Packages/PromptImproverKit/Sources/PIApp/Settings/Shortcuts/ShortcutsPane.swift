import PIDesign
import SwiftUI

/// Settings › Shortcuts: a read-only reference. "Anywhere" holds the global shortcut, with a link
/// to change it in General; the panel's own shortcuts follow, from the injected groups.
struct ShortcutsPane: View {
    let groups: [ShortcutReferenceGroup]
    let shortcut: ShortcutFieldModel
    let changeShortcut: () -> Void

    var body: some View {
        SettingsPaneContainer(SettingsPane.shortcuts.title) {
            SettingsSection(SettingsStrings.text("settings.shortcuts.anywhere.section")) {
                SettingsRow(title: SettingsStrings.text("settings.shortcuts.open"), compact: true) {
                    HStack(spacing: EmberDesign.Spacing.s) {
                        Group {
                            if shortcut.caps.isEmpty || shortcut.isRecording {
                                Text(verbatim: SettingsStrings.text("settings.shortcut.none"))
                                    .font(SettingsLayout.subtitleFont)
                                    .foregroundStyle(.secondary)
                            } else {
                                EKeyCapGroup(caps: shortcut.caps)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: shortcut.spokenShortcut))
                        Button(SettingsStrings.text("settings.shortcuts.change"), action: changeShortcut)
                            .buttonStyle(.ember(.secondary))
                    }
                }
            }

            ForEach(groups) { group in
                SettingsSection(group.title) {
                    ForEach(group.rows) { row in
                        SettingsRow(title: row.label, compact: true) {
                            EKeyCapGroup(row.chord)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: row.label))
                        .accessibilityValue(Text(verbatim: ShortcutGlyphFormatter.string(for: row.chord)))
                    }
                }
            }
        }
    }
}
