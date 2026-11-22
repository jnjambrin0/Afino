import Foundation
import PIFoundation
import PIPrompts
import PIProviders
import Testing
@testable import PICore

@MainActor
struct SettingsModelTests {
    private let defaults = EphemeralDefaults()

    @Test
    func defaultsAreBalancedAnthropicAndNothingIsStored() {
        let settings = SettingsModel(store: ConfigStore(defaults: defaults.defaults))
        #expect(settings.provider == .anthropic)
        #expect(settings.preset == .balanced)
        #expect(settings.engineSelection.model == "claude-sonnet-5-5")
        #expect(settings.historyEnabled)
        #expect(settings.outputLanguage == .matchDraft)
        #expect(settings.initialTargetID == nil)
        #expect(defaults.defaults.object(forKey: "enginePreset") == nil)
    }

    @Test
    func changesPersistAcrossInstances() {
        let store = ConfigStore(defaults: defaults.defaults)
        let settings = SettingsModel(store: store)
        settings.provider = .openai
        settings.preset = .custom(model: "gpt-6.1-terra", effort: .low)
        settings.defaultTarget = .fixed(id: "gemini")
        settings.customInstructions = "No persona line."
        settings.outputLanguage = .english
        settings.historyEnabled = false
        settings.appearance = .dark

        let reloaded = SettingsModel(store: store)
        #expect(reloaded.provider == .openai)
        #expect(reloaded.preset == .custom(model: "gpt-6.1-terra", effort: .low))
        #expect(reloaded.engineSelection.model == "gpt-6.1-terra")
        #expect(reloaded.initialTargetID == "gemini")
        #expect(reloaded.promptPreferences.effectiveCustomInstructions == "No persona line.")
        #expect(reloaded.promptPreferences.language == .english)
        #expect(!reloaded.historyEnabled)
        #expect(reloaded.appearance == .dark)
    }

    @Test
    func presetsResolvePerProvider() {
        let settings = SettingsModel(store: ConfigStore(defaults: defaults.defaults))
        settings.preset = .quality
        #expect(settings.engineSelection.model == "claude-opus-5-5")
        settings.provider = .openai
        #expect(settings.engineSelection.model == "gpt-6.2-astra")
        settings.preset = .fast
        #expect(settings.engineSelection.model == "gpt-6-luna")
    }
}
