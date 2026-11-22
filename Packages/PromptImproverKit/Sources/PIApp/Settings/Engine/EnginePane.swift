import PICore
import PIDesign
import PIProviders
import SwiftUI

/// Settings › Engine: which provider and model rewrite the prompts, and the API keys.
struct EnginePane: View {
    let context: SettingsContext
    let model: SettingsWindowModel

    private var settings: SettingsModel { context.settings }

    var body: some View {
        SettingsPaneContainer(SettingsPane.engine.title) {
            rewriteSection
            keysSection
        }
    }

    // MARK: Rewrite with

    private var rewriteSection: some View {
        SettingsSection(SettingsStrings.text("settings.engine.rewrite.section")) {
            SettingsRow(title: SettingsStrings.text("settings.engine.provider.title")) {
                EChoiceChips(
                    SettingsStrings.text("settings.engine.provider.title"),
                    options: EngineOptions.providerOptions(selected: settings.provider, state: context.vault.state(for:)),
                    selection: Binding(
                        get: {
                            ProviderOption(provider: settings.provider, isEnabled: true)
                        },
                        set: { option in switchProvider(to: option.provider) }
                    ),
                    isAvailable: \.isEnabled,
                    unavailableHelp: { _ in SettingsStrings.text("settings.engine.provider.needsKey") },
                    title: { $0.provider.displayName }
                )
                .fixedSize()
            }

            SettingsRow(title: SettingsStrings.text("settings.engine.model.title")) {
                VStack(alignment: .trailing, spacing: EmberDesign.Spacing.xxs) {
                    EChoiceChips(
                        SettingsStrings.text("settings.engine.model.title"),
                        options: EngineOptions.presetChoices,
                        selection: Binding(
                            get: { EngineOptions.choice(for: settings.preset) },
                            set: { choice in
                                settings.preset = EngineOptions.preset(for: choice, current: settings.preset, provider: settings.provider)
                            }
                        ),
                        title: \.title
                    )
                    .fixedSize()
                    Text(verbatim: EngineOptions.resolvedModelID(for: settings.preset, provider: settings.provider))
                        .font(SettingsLayout.modelIDFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.trailing, EmberDesign.Control.smallHorizontalPadding)
                }
            }

            if case .custom(let modelID, _) = settings.preset {
                customModelRow(modelID: modelID)
                modelIDRow(modelID: modelID)
                effortRow
            }
        }
    }

    private func switchProvider(to provider: ProviderID) {
        guard provider != settings.provider else { return }
        let previous = settings.provider
        settings.provider = provider
        settings.preset = EngineOptions.preset(settings.preset, afterSwitchingFrom: previous, to: provider)
    }

    private func customModelRow(modelID: String) -> some View {
        let entries = context.catalog.entries(for: settings.provider)
        return SettingsRow(title: SettingsStrings.text("settings.engine.customModel.title")) {
            ESelect(
                SettingsStrings.text("settings.engine.customModel.title"),
                options: EngineOptions.modelChoices(entries: entries),
                selection: Binding(
                    get: { EngineOptions.modelChoice(for: modelID, entries: entries) },
                    set: { choice in
                        guard case .entry(let id) = choice else { return }
                        settings.preset = EngineOptions.preset(settings.preset, settingModel: id)
                    }
                ),
                minWidth: SettingsLayout.selectMinWidth,
                title: { choice in Self.title(for: choice, entries: entries) }
            )
        }
    }

    private static func title(for choice: ModelChoice, entries: [CatalogEntry]) -> String {
        switch choice {
        case .other:
            return SettingsStrings.text("settings.engine.customModel.other")
        case .entry(let id):
            guard let entry = entries.first(where: { $0.model == id }) else { return id }
            return entry.isAvailable
                ? entry.displayName
                : SettingsStrings.text("settings.engine.customModel.unavailable", entry.displayName)
        }
    }

    private func modelIDRow(modelID: String) -> some View {
        SettingsRow(title: SettingsStrings.text("settings.engine.modelID.title")) {
            EField(
                SettingsStrings.text(
                    "settings.engine.modelID.placeholder",
                    EngineOptions.resolvedModelID(for: .quality, provider: settings.provider)
                ),
                text: Binding(
                    get: { modelID },
                    set: { settings.preset = EngineOptions.preset(settings.preset, settingModel: $0) }
                ),
                accessibilityLabel: SettingsStrings.text("settings.engine.modelID.title"),
                isInvalid: modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                font: .body.monospaced()
            )
            .frame(width: SettingsLayout.modelIDFieldWidth)
        }
    }

    @ViewBuilder
    private var effortRow: some View {
        let options = EngineOptions.effortOptions(for: settings.preset, provider: settings.provider)
        if !options.isEmpty {
            SettingsRow(
                title: SettingsStrings.text("settings.engine.effort.title"),
                subtitle: SettingsStrings.text("settings.engine.effort.help")
            ) {
                EChoiceChips(
                    SettingsStrings.text("settings.engine.effort.title"),
                    options: options,
                    selection: Binding(
                        get: { EngineOptions.selectedEffort(for: settings.preset, provider: settings.provider) ?? .medium },
                        set: { settings.preset = EngineOptions.preset(settings.preset, settingEffort: $0) }
                    ),
                    title: \.settingsTitle
                )
                .fixedSize()
            }
        }
    }

    // MARK: API keys

    private var keysSection: some View {
        SettingsSection(
            SettingsStrings.text("settings.engine.keys.section"),
            footer: SettingsStrings.text("settings.engine.keys.footer")
        ) {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                EKeyField(
                    model: context.keyEntry(for: provider),
                    onRemove: { confirmRemoval(of: provider) },
                    openURL: context.openURL
                )
                .settingsRowPadding()
            }
        }
    }

    private func confirmRemoval(of provider: ProviderID) {
        let entry = context.keyEntry(for: provider)
        model.dialog = SettingsDialog(
            title: SettingsStrings.text("settings.key.remove.title", provider.displayName),
            message: SettingsStrings.text("settings.key.remove.message", provider.displayName),
            symbol: "key",
            actions: [
                .init(title: SettingsStrings.text("settings.key.cancel"), role: .cancel) {},
                .init(title: SettingsStrings.text("settings.key.remove"), role: .destructive) { entry.remove() },
            ]
        )
    }
}
