import PICore
import PIDesign
import PIPrompts
import SwiftUI

/// Settings › General: how Afino opens, where a prompt starts, the theme and the history.
struct GeneralPane: View {
    let context: SettingsContext

    @State private var historyCleared = false
    @State private var historyClearFailed = false
    @State private var isClearingHistory = false

    private var settings: SettingsModel { context.settings }
    private var launchAtLogin: LaunchAtLoginModel { context.launchAtLogin }

    var body: some View {
        SettingsPaneContainer(SettingsPane.general.title) {
            launcherSection
            promptsSection
            appearanceSection
            privacySection
        }
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: Launcher

    private var launcherSection: some View {
        SettingsSection(SettingsStrings.text("settings.general.launcher.section")) {
            VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
                SettingsRow(
                    title: SettingsStrings.text("settings.general.shortcut.title"),
                    subtitle: SettingsStrings.text("settings.general.shortcut.help")
                ) {
                    ShortcutRecorderField(model: context.shortcut)
                }
                if let warning = context.shortcut.displayedWarning {
                    EInlineMessage(warning.text, tone: .warning)
                        .padding(.horizontal, EmberDesign.Settings.rowHorizontalPadding)
                        .padding(.bottom, EmberDesign.Settings.rowVerticalPadding)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: SettingsStrings.text("settings.general.login.title"),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled || launchAtLogin.requiresApproval },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if launchAtLogin.requiresApproval || launchAtLogin.errorMessage != nil {
                    loginFeedback
                }
            }
        }
    }

    private var loginFeedback: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.s) {
            if let error = launchAtLogin.errorMessage {
                EInlineMessage(SettingsStrings.text("settings.general.login.error", error), tone: .error)
            } else {
                EInlineMessage(SettingsStrings.text("settings.general.login.approval"), tone: .warning)
            }
            if launchAtLogin.requiresApproval {
                Button(SettingsStrings.text("settings.general.login.openSystemSettings")) {
                    launchAtLogin.openSystemSettings()
                }
                .buttonStyle(.ember(.secondary))
            }
        }
        .padding(.horizontal, EmberDesign.Settings.rowHorizontalPadding)
        .padding(.bottom, EmberDesign.Settings.rowVerticalPadding)
    }

    // MARK: Prompts

    private var promptsSection: some View {
        SettingsSection(SettingsStrings.text("settings.general.prompts.section")) {
            SettingsRow(title: SettingsStrings.text("settings.general.defaultTarget.title")) {
                ESelect(
                    SettingsStrings.text("settings.general.defaultTarget.title"),
                    options: DefaultTargetOptions.options(targets: context.targets),
                    selection: Binding(
                        get: { DefaultTargetOptions.selection(for: settings.defaultTarget, targets: context.targets) },
                        set: { settings.defaultTarget = $0 }
                    ),
                    minWidth: SettingsLayout.selectMinWidth,
                    monogram: { DefaultTargetOptions.monogram(for: $0, targets: context.targets) },
                    title: { DefaultTargetOptions.title(for: $0, targets: context.targets) }
                )
            }
            SettingsRow(title: SettingsStrings.text("settings.general.language.title")) {
                ESelect(
                    SettingsStrings.text("settings.general.language.title"),
                    options: [OutputLanguage.matchDraft, .english],
                    selection: Binding(get: { settings.outputLanguage }, set: { settings.outputLanguage = $0 }),
                    minWidth: SettingsLayout.selectMinWidth,
                    title: Self.title(for:)
                )
            }
        }
    }

    private static func title(for language: OutputLanguage) -> String {
        switch language {
        case .matchDraft: SettingsStrings.text("settings.general.language.matchDraft")
        case .english: SettingsStrings.text("settings.general.language.english")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsSection(SettingsStrings.text("settings.general.appearance.section")) {
            SettingsRow(title: SettingsStrings.text("settings.general.theme.title")) {
                EChoiceChips(
                    SettingsStrings.text("settings.general.theme.title"),
                    options: AppearanceSetting.allCases,
                    selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0 }),
                    title: \.settingsTitle
                )
                .fixedSize()
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        SettingsSection(SettingsStrings.text("settings.general.privacy.section")) {
            SettingsToggleRow(
                title: SettingsStrings.text("settings.general.history.title"),
                subtitle: SettingsStrings.text("settings.general.history.help"),
                isOn: Binding(get: { settings.historyEnabled }, set: { settings.historyEnabled = $0 })
            )
            SettingsRow(
                title: SettingsStrings.text("settings.general.clearHistory.title"),
                subtitle: historyClearFailed
                    ? SettingsStrings.text("settings.general.clearHistory.failed")
                    : SettingsStrings.text("settings.general.clearHistory.help")
            ) {
                SettingsOneShotButton(
                    title: SettingsStrings.text("settings.general.clearHistory.button"),
                    doneTitle: SettingsStrings.text("settings.general.clearHistory.done"),
                    isDone: historyCleared,
                    isDisabled: isClearingHistory,
                    action: clearHistory
                )
            }
        }
    }

    private func clearHistory() {
        isClearingHistory = true
        Task {
            let cleared = await context.clearHistory()
            isClearingHistory = false
            historyCleared = cleared
            historyClearFailed = !cleared
        }
    }
}
