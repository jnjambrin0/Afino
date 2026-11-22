@testable import PIApp
import PICore
import PIProviders
import Testing

/// What Settings › Engine offers for each preset and provider.
struct EngineOptionsTests {
    @Test(arguments: [
        (EnginePreset.quality, ProviderID.anthropic, "claude-opus-5-5"),
        (.balanced, .anthropic, "claude-sonnet-5-5"),
        (.fast, .anthropic, "claude-haiku-5-5"),
        (.quality, .openai, "gpt-6.2-astra"),
        (.balanced, .openai, "gpt-6.2-sol"),
        (.fast, .openai, "gpt-6-luna"),
        (.custom(model: "claude-fable-5-2", effort: .high), .anthropic, "claude-fable-5-2"),
        (.custom(model: "  my-model  ", effort: nil), .openai, "my-model"),
    ])
    func theResolvedModelIsShownUnderTheChips(preset: EnginePreset, provider: ProviderID, model: String) {
        #expect(EngineOptions.resolvedModelID(for: preset, provider: provider) == model)
    }

    @Test func chipsMapToPresetsAndBack() {
        #expect(EngineOptions.presetChoices == [.quality, .balanced, .fast, .custom])
        for choice in [PresetChoice.quality, .balanced, .fast] {
            let preset = EngineOptions.preset(for: choice, current: .balanced, provider: .anthropic)
            #expect(EngineOptions.choice(for: preset) == choice)
        }
        #expect(EngineOptions.choice(for: .custom(model: "x", effort: nil)) == .custom)
    }

    @Test(arguments: [
        (EnginePreset.quality, ProviderID.anthropic, EnginePreset.custom(model: "claude-opus-5-5", effort: .medium)),
        (.balanced, .anthropic, .custom(model: "claude-sonnet-5-5", effort: .low)),
        (.fast, .anthropic, .custom(model: "claude-haiku-5-5", effort: .low)),
        (.balanced, .openai, .custom(model: "gpt-6.2-sol", effort: .low)),
        (.fast, .openai, .custom(model: "gpt-6-luna", effort: Effort.none)),
    ])
    func customStartsFromWhatRunsNow(current: EnginePreset, provider: ProviderID, expected: EnginePreset) {
        #expect(EngineOptions.preset(for: .custom, current: current, provider: provider) == expected)
    }

    @Test func choosingCustomAgainKeepsTheCustomModel() {
        let custom = EnginePreset.custom(model: "claude-fable-5-2", effort: .high)
        #expect(EngineOptions.preset(for: .custom, current: custom, provider: .anthropic) == custom)
    }

    @Test func effortChipsAreLimitedToWhatTheModelAccepts() {
        #expect(EngineOptions.effortOptions(for: .custom(model: "claude-opus-5-5", effort: nil), provider: .anthropic) == [.low, .medium, .high])
        #expect(EngineOptions.effortOptions(for: .custom(model: "unknown-model", effort: nil), provider: .openai) == [.low, .medium, .high])

        var capabilities = ModelCapabilities.conservative
        capabilities.supportedEfforts = [.none, .low, .xhigh]
        #expect(EngineOptions.effortOptions(for: capabilities) == [.low])
        capabilities.supportedEfforts = [.max]
        #expect(EngineOptions.effortOptions(for: capabilities).isEmpty)
    }

    @Test func theChosenEffortIsTheOneSent() {
        #expect(EngineOptions.selectedEffort(for: .custom(model: "claude-opus-5-5", effort: .high), provider: .anthropic) == .high)
        // No effort chosen: the model's default.
        #expect(EngineOptions.selectedEffort(for: .custom(model: "claude-opus-5-5", effort: nil), provider: .anthropic) == .medium)
        #expect(EngineOptions.selectedEffort(for: .balanced, provider: .anthropic) == .low)
    }

    @Test func effortAndModelOnlyChangeACustomPreset() {
        let custom = EnginePreset.custom(model: "claude-opus-5-5", effort: .low)
        #expect(EngineOptions.preset(custom, settingEffort: .high) == .custom(model: "claude-opus-5-5", effort: .high))
        #expect(EngineOptions.preset(custom, settingModel: "claude-fable-5-2") == .custom(model: "claude-fable-5-2", effort: .low))
        #expect(EngineOptions.preset(.balanced, settingEffort: .high) == .balanced)
        #expect(EngineOptions.preset(.fast, settingModel: "x") == .fast)
    }

    @Test func theModelPickerListsTheCatalogThenOther() {
        let entries = ModelCatalog.curated(for: .anthropic)
        let choices = EngineOptions.modelChoices(entries: entries)
        #expect(choices.count == entries.count + 1)
        #expect(choices.last == .other)
        #expect(choices.first == .entry(entries[0].model))
        #expect(EngineOptions.modelChoice(for: "claude-fable-5-2", entries: entries) == .entry("claude-fable-5-2"))
        #expect(EngineOptions.modelChoice(for: "my-fine-tune", entries: entries) == .other)
    }

    @Test func aProviderWithoutAUsableKeyIsUnavailableUnlessChosen() {
        let states: [ProviderID: KeyState] = [.anthropic: .valid(masked: "sk-…a1b2"), .openai: .invalid(masked: "sk-…9f3c")]
        let options = EngineOptions.providerOptions(selected: .anthropic) { states[$0] ?? .missing }
        #expect(options == [
            ProviderOption(provider: .anthropic, isEnabled: true),
            ProviderOption(provider: .openai, isEnabled: false),
        ])

        let unverified = EngineOptions.providerOptions(selected: .anthropic) { _ in .unverified(masked: "sk-…") }
        #expect(unverified.allSatisfy { $0.isEnabled })

        let none = EngineOptions.providerOptions(selected: .openai) { _ in .missing }
        #expect(none == [
            ProviderOption(provider: .anthropic, isEnabled: false),
            ProviderOption(provider: .openai, isEnabled: true),
        ])
    }

    @Test func switchingProviderReplacesACustomModelOfTheOtherProvider() {
        let claude = EnginePreset.custom(model: "claude-opus-5-5", effort: .high)
        #expect(EngineOptions.preset(claude, afterSwitchingFrom: .anthropic, to: .openai) == .custom(model: "gpt-6.2-sol", effort: .high))

        let own = EnginePreset.custom(model: "my-fine-tune", effort: .low)
        #expect(EngineOptions.preset(own, afterSwitchingFrom: .anthropic, to: .openai) == own)
        #expect(EngineOptions.preset(.quality, afterSwitchingFrom: .anthropic, to: .openai) == .quality)
    }
}
