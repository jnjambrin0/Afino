import AppKit
import PICore
import PIProviders

/// Everything the Settings panes read and change. The window controller builds it from
/// `AppServices`; tests build one from fakes.
struct SettingsContext {
    let settings: SettingsModel
    let vault: any KeyVaulting
    let catalog: ModelCatalogStore
    /// The targets, in picker order.
    let targets: [TargetSummary]
    let launchAtLogin: LaunchAtLoginModel
    let shortcut: ShortcutFieldModel
    let updates: UpdateController
    let version: AppVersion
    /// One key field per provider, kept for the life of the window so a check in progress
    /// survives switching panes.
    let keyEntries: [ProviderID: KeyEntryModel]
    /// Deletes the saved history; false when it could not.
    let clearHistory: () async -> Bool
    let openURL: (URL) -> Void

    init(
        settings: SettingsModel,
        vault: any KeyVaulting,
        catalog: ModelCatalogStore,
        targets: [TargetSummary],
        launchAtLogin: LaunchAtLoginModel,
        shortcut: ShortcutFieldModel,
        updates: UpdateController,
        version: AppVersion = .current(),
        readClipboard: @escaping () -> String? = { NSPasteboard.general.string(forType: .string) },
        clearHistory: @escaping () async -> Bool,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.settings = settings
        self.vault = vault
        self.catalog = catalog
        self.targets = targets
        self.launchAtLogin = launchAtLogin
        self.shortcut = shortcut
        self.updates = updates
        self.version = version
        self.clearHistory = clearHistory
        self.openURL = openURL
        var entries: [ProviderID: KeyEntryModel] = [:]
        for provider in ProviderID.allCases {
            let entry = KeyEntryModel(provider: provider, vault: vault, readClipboard: readClipboard)
            // A first key, or a key for the other provider while the chosen one has none: use it.
            entry.onSaved = { [settings, vault] saved in
                guard saved != settings.provider, !vault.state(for: settings.provider).isUsable else { return }
                let previous = settings.provider
                settings.provider = saved
                settings.preset = EngineOptions.preset(settings.preset, afterSwitchingFrom: previous, to: saved)
            }
            entries[provider] = entry
        }
        keyEntries = entries
    }

    func keyEntry(for provider: ProviderID) -> KeyEntryModel {
        // Every provider has one, made in `init`.
        keyEntries[provider] ?? KeyEntryModel(provider: provider, vault: vault) { nil }
    }
}

/// The app's name, and its version and build as the Info.plist states them.
struct AppVersion: Equatable, Sendable {
    let name: String
    let version: String
    let build: String

    static func current(bundle: Bundle = .main) -> AppVersion {
        let info = bundle.infoDictionary ?? [:]
        return AppVersion(
            name: AppStrings.appName,
            version: info["CFBundleShortVersionString"] as? String ?? "—",
            build: info["CFBundleVersion"] as? String ?? "—"
        )
    }

    /// "Version 2.0.0 (7)".
    var displayString: String {
        SettingsStrings.text("settings.about.version", version, build)
    }
}

extension AppearanceSetting {
    /// What `NSApp.appearance` is set to: nil follows the system.
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var settingsTitle: String {
        switch self {
        case .system: SettingsStrings.text("settings.general.theme.system")
        case .light: SettingsStrings.text("settings.general.theme.light")
        case .dark: SettingsStrings.text("settings.general.theme.dark")
        }
    }
}
