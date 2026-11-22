import Foundation
import PIFoundation
import PIPrompts
import PIProviders
@testable import PICore

/// A provider whose streams are driven by the test: each `stream` call hands back a continuation
/// the test feeds, so the order of events across two runs is exact.
final class ScriptedProvider: PromptEngineProvider, @unchecked Sendable {
    let id: ProviderID
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<EngineEvent, any Error>.Continuation] = []
    private var recordedRequests: [EngineRequest] = []
    var modelsResult: Result<[RemoteModel], EngineFailure> = .success([])

    init(id: ProviderID = .anthropic) {
        self.id = id
    }

    var requests: [EngineRequest] { lock.withLock { recordedRequests } }

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                recordedRequests.append(request)
                continuations.append(continuation)
            }
        }
    }

    func models(key: APIKey) async throws -> [RemoteModel] {
        try modelsResult.get()
    }

    func prewarm() async {}

    /// Sends events on the stream of the `run`-th request (0-based).
    func send(_ events: EngineEvent..., toRun run: Int) {
        let continuation = lock.withLock { continuations[run] }
        for event in events { continuation.yield(event) }
    }

    func finish(run: Int, throwing error: (any Error)? = nil) {
        let continuation = lock.withLock { continuations[run] }
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }
}

@MainActor
final class RecordingClipboard: ClipboardWriting {
    private(set) var writes: [String] = []
    func write(_ text: String) { writes.append(text) }
}

@MainActor
struct SessionFixture {
    let defaults: EphemeralDefaults
    let settings: SettingsModel
    let vault: CredentialVault
    let provider: ScriptedProvider
    let clipboard: RecordingClipboard
    let history: HistoryStore
    let session: ImproveSession
    let historyFile: URL

    init(storedKey: String? = "sk-ant-test-key-1234", historyEnabled: Bool = true) throws {
        defaults = EphemeralDefaults()
        let config = ConfigStore(defaults: defaults.defaults)
        settings = SettingsModel(store: config)
        settings.historyEnabled = historyEnabled
        provider = ScriptedProvider()
        let secrets = InMemorySecretStore(storedKey.map { ["anthropic": $0] } ?? [:])
        vault = CredentialVault(store: secrets, config: config, providers: [.anthropic: provider])
        vault.loadStoredKeys()
        clipboard = RecordingClipboard()
        historyFile = FileManager.default.temporaryDirectory
            .appending(path: "AfinoSessionTests-\(UUID().uuidString)/history.json")
        history = HistoryStore(fileURL: historyFile)
        session = ImproveSession(
            settings: settings,
            vault: vault,
            library: try TargetPackLibrary.bundled(),
            composer: try PromptComposer.bundled(),
            providers: [.anthropic: provider],
            clipboard: clipboard,
            history: history,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    /// Lets the session's task consume what the test sent.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }
}
