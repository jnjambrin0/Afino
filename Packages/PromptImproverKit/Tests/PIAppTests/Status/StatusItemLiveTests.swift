import AppKit
@testable import PIApp
import PICore
import PIFoundation
import PIPrompts
import PIProviders
import Testing

/// Puts a real menu bar item on screen, drives a session through a run that completes and one
/// that fails, and captures the item at each step as PNGs for a person to look at. Opt-in, like
/// the Settings snapshots: `PI_SETTINGS_SNAPSHOTS=<folder> swift test --filter StatusItemLiveTests`.
@Suite(.serialized)
struct StatusItemLiveTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["PI_SETTINGS_SNAPSHOTS"].map { URL(filePath: $0) }

    @Test(.enabled(if: folder != nil))
    func theIconFollowsARun() async throws {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let defaults = EphemeralDefaults()
        let config = ConfigStore(defaults: defaults.defaults)
        let settings = SettingsModel(store: config)
        let provider = ControlledProvider()
        let vault = CredentialVault(
            store: InMemorySecretStore(["anthropic": SettingsSamples.anthropicKey]),
            config: config,
            providers: [.anthropic: provider]
        )
        vault.loadStoredKeys()
        let session = ImproveSession(
            settings: settings,
            vault: vault,
            library: try TargetPackLibrary.bundled(),
            composer: try PromptComposer.bundled(),
            providers: [.anthropic: provider],
            clipboard: SilentClipboard(),
            history: nil
        )
        let actions = AppMenuActions(showPanel: {}, showSettings: {}, checkForUpdates: {}, canCheckForUpdates: { false }, showAbout: {})
        let controller = StatusItemController(
            actions: actions,
            session: session,
            settings: settings,
            activationShortcut: ActivationShortcut(config: config, hotKeys: HotKeyCenter()),
            clipboard: SilentClipboard(),
            isPanelVisible: { false }
        )
        try await Task.sleep(for: .seconds(1))

        try capture(controller, "status-icon-1-idle", folder)

        session.setDraft("write a haiku about the sea")
        session.submit()
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.iconState == .running)
        try capture(controller, "status-icon-2-running-a", folder)
        try await Task.sleep(for: .milliseconds(550))
        try capture(controller, "status-icon-2-running-b", folder)

        provider.send(.started(servedModel: "claude-sonnet-5-5", requestID: nil), .textDelta("Waves fold into foam."), .finished(.complete, usage: nil))
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.iconState == .done)
        #expect(controller.lastResult == "Waves fold into foam.")
        try capture(controller, "status-icon-3-done", folder)

        try await Task.sleep(for: .seconds(2.6))
        #expect(controller.iconState == .idle)
        try capture(controller, "status-icon-4-idle-again", folder)

        session.newPrompt()
        session.setDraft("another one")
        session.submit()
        try await Task.sleep(for: .milliseconds(200))
        provider.fail(EngineFailure(.offline, provider: .anthropic))
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.iconState == .attention(.runFailed))
        try capture(controller, "status-icon-5-failed", folder)

        controller.panelDidOpen()
        #expect(controller.iconState == .idle)
    }

    /// The item and a little of the menu bar around it, as the window server draws them.
    private func capture(_ controller: StatusItemController, _ name: String, _ folder: URL) throws {
        let frame = try #require(controller.buttonFrameOnScreen)
        let screenHeight = try #require(NSScreen.screens.first?.frame.height)
        let margin: CGFloat = 24
        let region = [frame.minX - margin, screenHeight - frame.maxY - 4, frame.width + margin * 2, frame.height + 8]
            .map { String(Int($0.rounded())) }.joined(separator: ",")
        let screencapture = Process()
        screencapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-x", "-R", region, folder.appending(path: "\(name).png").path]
        try screencapture.run()
        screencapture.waitUntilExit()
    }
}

/// Streams whatever the test sends.
private nonisolated final class ControlledProvider: PromptEngineProvider, @unchecked Sendable {
    let id = ProviderID.anthropic
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<EngineEvent, any Error>.Continuation?

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func models(key: APIKey) async throws -> [RemoteModel] { [] }

    func prewarm() async {}

    func send(_ events: EngineEvent...) {
        let continuation = lock.withLock { self.continuation }
        for event in events { continuation?.yield(event) }
        continuation?.finish()
    }

    func fail(_ error: any Error) {
        lock.withLock { continuation }?.finish(throwing: error)
    }
}

/// Never touches the user's clipboard.
private final class SilentClipboard: ClipboardWriting {
    func write(_ text: String) {}
}
