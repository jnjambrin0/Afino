import AppKit
import PICore
import PIDesign
import SwiftUI

/// Settings › About: the version, updates, links, acknowledgements, and a way to see the welcome
/// again.
struct AboutPane: View {
    let context: SettingsContext
    let model: SettingsWindowModel

    /// The welcome window opens as soon as `onboardingCompleted` turns false; the button then
    /// shows that it has.
    @State private var welcomeScheduled = false

    private var updates: UpdateController { context.updates }

    static let websiteURL = URL(string: "https://github.com/jnjambrin0/Afino")!
    static let releaseNotesURL = URL(string: "https://github.com/jnjambrin0/Afino/releases")!

    var body: some View {
        SettingsPaneContainer(SettingsPane.about.title) {
            SettingsSection(footer: updatesFooter) {
                HStack(alignment: .center, spacing: EmberDesign.Spacing.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: EmberDesign.Settings.appIconSize, height: EmberDesign.Settings.appIconSize)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: EmberDesign.Spacing.xxs) {
                        Text(verbatim: context.version.name)
                            .font(SettingsLayout.appNameFont)
                        Text(verbatim: context.version.displayString)
                            .font(SettingsLayout.subtitleFont)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(SettingsStrings.text("settings.about.checkForUpdates")) {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(.ember(.secondary))
                    .disabled(!updates.canCheckForUpdates)
                }
                .settingsRowPadding()

                SettingsToggleRow(
                    title: SettingsStrings.text("settings.about.automatic"),
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.automaticallyChecksForUpdates = $0 }
                    )
                )
                .disabled(updates.suppression != nil)
            }

            SettingsSection(SettingsStrings.text("settings.about.links.section")) {
                SettingsLinkRow(title: SettingsStrings.text("settings.about.releaseNotes")) {
                    context.openURL(Self.releaseNotesURL)
                }
                SettingsLinkRow(title: SettingsStrings.text("settings.about.website")) {
                    context.openURL(Self.websiteURL)
                }
                SettingsLinkRow(title: SettingsStrings.text("settings.about.acknowledgements"), destination: .inApp) {
                    model.dialog = SettingsDialog(
                        title: SettingsStrings.text("settings.about.acknowledgements"),
                        message: SettingsStrings.text("settings.about.acknowledgements.message"),
                        symbol: "heart",
                        actions: [.init(title: SettingsStrings.text("settings.about.done"), role: .confirm) {}]
                    )
                }
                SettingsRow(
                    title: SettingsStrings.text("settings.about.welcome"),
                    subtitle: SettingsStrings.text("settings.about.welcome.help")
                ) {
                    SettingsOneShotButton(
                        title: SettingsStrings.text("settings.about.welcome.button"),
                        doneTitle: SettingsStrings.text("settings.about.welcome.done"),
                        isDone: welcomeScheduled
                    ) {
                        context.settings.onboardingCompleted = false
                        welcomeScheduled = true
                    }
                }
            }
        }
    }

    /// Why updates are off on this copy, if they are.
    private var updatesFooter: String? {
        switch updates.suppression {
        case nil: nil
        case .debugBuild: SettingsStrings.text("settings.about.updatesOff.debug")
        case .notUpdatableLocation: SettingsStrings.text("settings.about.updatesOff.location")
        case .missingFeedURL, .missingPublicKey: SettingsStrings.text("settings.about.updatesOff.build")
        }
    }
}
