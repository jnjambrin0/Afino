import AppKit
@testable import PIApp
import PICore
import PIFoundation
import PIProviders
import Testing

/// What Settings does beyond a single control: switching to the provider that has a key,
/// remembering the pane, applying the theme.
struct SettingsContextTests {
    @Test func aFirstKeyForTheOtherProviderSwitchesToIt() async {
        let fixture = SettingsFixture()
        fixture.settings.preset = .custom(model: "claude-opus-5-5", effort: .high)
        let entry = fixture.context.keyEntry(for: .openai)

        entry.draft = SettingsSamples.openAIKey
        await entry.save()

        #expect(fixture.settings.provider == .openai)
        // A Claude model would only fail on OpenAI.
        #expect(fixture.settings.preset == .custom(model: "gpt-6.2-sol", effort: .high))
    }

    @Test func aKeyForTheOtherProviderLeavesAWorkingChoiceAlone() async {
        let fixture = SettingsFixture(vault: FakeVault([.anthropic: .valid(masked: "sk-…a1b2")]))
        let entry = fixture.context.keyEntry(for: .openai)

        entry.draft = SettingsSamples.openAIKey
        await entry.save()

        #expect(fixture.settings.provider == .anthropic)
    }

    @Test func aRejectedKeySwitchesNothing() async {
        let vault = FakeVault()
        vault.saveOutcome = .rejected
        let fixture = SettingsFixture(vault: vault)
        let entry = fixture.context.keyEntry(for: .openai)

        entry.draft = SettingsSamples.openAIKey
        await entry.save()

        #expect(fixture.settings.provider == .anthropic)
    }

    @Test func everyProviderHasItsOwnField() {
        let fixture = SettingsFixture()
        for provider in ProviderID.allCases {
            #expect(fixture.context.keyEntry(for: provider).provider == provider)
            #expect(fixture.context.keyEntry(for: provider) === fixture.context.keyEntry(for: provider))
        }
    }

    @Test func theLastPaneIsOpenedAgain() {
        let defaults = EphemeralDefaults()
        let config = ConfigStore(defaults: defaults.defaults)
        #expect(SettingsWindowModel(config: config).selectedPane == .general)

        SettingsWindowModel(config: config).selectedPane = .engine

        #expect(SettingsWindowModel(config: config).selectedPane == .engine)
    }

    @Test func aPaneSavedByAnotherVersionFallsBackToGeneral() {
        let defaults = EphemeralDefaults()
        defaults.defaults.set("billing", forKey: "settingsSelectedPane")
        #expect(SettingsWindowModel(config: ConfigStore(defaults: defaults.defaults)).selectedPane == .general)
    }

    @Test func thePanesAreInSidebarOrderWithTheirSymbols() {
        #expect(SettingsPane.allCases == [.general, .engine, .instructions, .shortcuts, .about])
        #expect(SettingsPane.allCases.map(\.systemImage) == ["gearshape", "cpu", "text.quote", "command", "info.circle"])
        #expect(SettingsPane.allCases.allSatisfy { !$0.title.hasPrefix("settings.") })
    }

    @Test func theThemeMapsToAnAppKitAppearance() {
        #expect(AppearanceSetting.system.appKitAppearance == nil)
        #expect(AppearanceSetting.light.appKitAppearance?.name == .aqua)
        #expect(AppearanceSetting.dark.appKitAppearance?.name == .darkAqua)
    }

    @Test func theVersionComesFromTheBundle() {
        let version = AppVersion(name: "Afino", version: "2.0.0", build: "7")
        #expect(version.displayString.contains("2.0.0"))
        #expect(version.displayString.contains("(7)"))
        #expect(AppVersion.current(bundle: Bundle(for: FakeActivator.self)).name == "Afino")
    }

    @Test func eachProviderLinksToItsConsole() {
        #expect(EKeyField.consoleURL(for: .anthropic).absoluteString == "https://console.anthropic.com/settings/keys")
        #expect(EKeyField.consoleURL(for: .openai).absoluteString == "https://platform.openai.com/api-keys")
    }
}
