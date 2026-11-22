import Foundation
import PICore
import PIFoundation
import PIPrompts
import PIProviders

/// The long-lived services of the app, created once at launch by `AppDelegate` and handed down
/// by initializer to whoever needs them. Nothing reaches for a shared instance.
struct AppServices {
    let config: ConfigStore
    /// The one seam through which the app asks to become active.
    let activator: any AppActivating
    let hotKeys: HotKeyCenter
    let activationShortcut: ActivationShortcut
    /// Software updates; never started on Debug builds or where an update cannot replace the app.
    let updates: UpdateController
    let launchAtLogin: LaunchAtLoginModel

    /// Everything the user can set.
    let settings: SettingsModel
    /// The user's API keys and what the interface may show about them.
    let vault: CredentialVault
    let catalog: ModelCatalogStore
    let history: HistoryStore
    /// The prompt being improved. One for the life of the app: the panel shows it, and a run
    /// carries on while the panel is hidden.
    let session: ImproveSession

    init(
        config: ConfigStore,
        activator: any AppActivating,
        installLocation: any InstallLocationManaging,
        loginItems: any LoginItemServicing = LoginItemService(),
        secrets: any SecretStore = AppServices.makeSecretStore()
    ) throws {
        let hotKeys = HotKeyCenter()
        self.config = config
        self.activator = activator
        self.hotKeys = hotKeys
        activationShortcut = ActivationShortcut(config: config, hotKeys: hotKeys)
        updates = UpdateController(
            isDebugBuild: Self.isDebugBuild,
            isUpdatableLocation: installLocation.evaluateInstallState() == .updatable,
            activator: activator
        )
        launchAtLogin = LaunchAtLoginModel(service: loginItems)

        let urlSession = ProviderSession.make()
        let providers: [ProviderID: any PromptEngineProvider] = [
            .anthropic: AnthropicProvider(session: urlSession),
            .openai: OpenAIProvider(session: urlSession),
        ]
        let settings = SettingsModel(store: config)
        self.settings = settings
        let catalog = ModelCatalogStore()
        self.catalog = catalog
        let vault = CredentialVault(store: secrets, config: config, providers: providers)
        vault.onModelsFetched = { provider, models in catalog.update(provider, remote: models) }
        self.vault = vault
        let history = HistoryStore()
        self.history = history
        // The packs and the engine prompt ship inside the app: failing to read them is a broken
        // build, reported at launch instead of on the first run.
        session = ImproveSession(
            settings: settings,
            vault: vault,
            library: try TargetPackLibrary.bundled(),
            composer: try PromptComposer.bundled(),
            providers: providers,
            clipboard: SystemClipboard(),
            history: history
        )
    }

    /// The Keychain, except in a development build started with API keys in its environment
    /// (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) or with `--in-memory-secrets`: contributors without
    /// the project's signing certificate would otherwise get a Keychain prompt on every rebuild.
    static func makeSecretStore() -> any SecretStore {
        #if DEBUG
        let variables = [ProviderID.anthropic.rawValue: "ANTHROPIC_API_KEY", ProviderID.openai.rawValue: "OPENAI_API_KEY"]
        let environment = ProcessInfo.processInfo.environment
        if variables.values.contains(where: { environment[$0]?.isEmpty == false }) {
            return EnvironmentSecretStore(variables: variables, environment: environment)
        }
        if ProcessInfo.processInfo.arguments.contains("--in-memory-secrets") {
            return InMemorySecretStore()
        }
        #endif
        return KeychainSecretStore()
    }

    /// `#if DEBUG` as a value, so the updater's rules can be tested with either answer.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
