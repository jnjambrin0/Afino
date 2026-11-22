#if DEBUG
import Foundation
import os
import PICore
import PIFoundation
import PIPrompts
import PIProviders

/// The panel demo, for Debug builds only: the panel runs against a scripted engine, so every state
/// (streaming, each failure, the add-a-key card, the history) can be seen and captured without an
/// API key, a network or a keyboard. Pass the flags as launch arguments, for example
/// `scripts/run.sh --demo-engine --demo-open --demo-draft "a snake game" --demo-submit`.
///
/// Any of these turns the demo on:
/// - `--demo-engine`: a canned multi-paragraph prompt streams in after a short "thinking" pause.
/// - `--demo-fail <case>`: the first run fails that way (later runs succeed, so Try Again works).
///   Cases: `invalidKey missingKey billing modelNotFound rateLimited rateLimitedNow overloaded
///   serverError offline timedOut secureConnection dropped droppedEarly refused truncated empty
///   malformed invalidRequest permissionDenied contextTooLong`.
/// - `--demo-setup`: no key is stored, so the add-a-key card shows (any key of 12 or more
///   characters without "bad" in it is accepted).
///
/// With the demo on, `--demo-retry` makes the first attempt report a retry ("Busy, retrying…")
/// before it starts. The demo keeps its settings in a throwaway defaults suite, its keys in memory
/// and its history in a temporary file seeded with a few entries; the real settings, Keychain and
/// history are never touched.
///
/// `PanelDemoDriver` then puts the panel into a state by itself, for screenshots:
/// - `--demo-open`: shows the panel shortly after launch; every flag below needs it.
/// - `--demo-draft <text>`: fills the compose input.
/// - `--demo-key <key>`: types a key into the add-a-key card and saves it; nothing else follows.
/// - `--demo-history`: opens the history list; nothing else follows.
/// - `--demo-menu actions|target`: opens the ⌘K menu or the target menu (after the run, when
///   there is one).
/// - `--demo-submit`: presses Return. The flags below act on the run it starts.
/// - `--demo-stop-after <ms>`: stops the run that many milliseconds in; nothing else follows.
/// - `--demo-refine <text>`: refines the result with that instruction.
/// - `--demo-target <id>`: switches to another target pack, so the result offers a rewrite.
/// - `--demo-refine-text <text>`: types into the refine field without sending it.
/// - `--demo-expand`: expands the original draft in the result header.
/// - `--demo-copy-close`: ends with Copy & Close.
struct PanelDemo {
    let session: ImproveSession
    let settings: SettingsModel
    let vault: CredentialVault
    let history: HistoryStore

    init?(arguments: [String]) {
        let failure = arguments.firstIndex(of: "--demo-fail").flatMap { index in
            arguments.indices.contains(index + 1) ? DemoFailure(rawValue: arguments[index + 1]) : nil
        }
        let showsSetup = arguments.contains("--demo-setup")
        guard arguments.contains("--demo-engine") || failure != nil || showsSetup,
              let library = try? TargetPackLibrary.bundled(),
              let composer = try? PromptComposer.bundled(),
              let defaults = UserDefaults(suiteName: Self.suiteName) else { return nil }
        defaults.removePersistentDomain(forName: Self.suiteName)
        let config = ConfigStore(defaults: defaults)
        settings = SettingsModel(store: config)
        let retries = arguments.contains("--demo-retry")
        let providers: [ProviderID: any PromptEngineProvider] = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, DemoEngineProvider(id: $0, failure: failure, retriesFirst: retries) as any PromptEngineProvider)
        })
        let secrets = InMemorySecretStore(showsSetup ? [:] : [ProviderID.anthropic.rawValue: "sk-ant-demo-key-0000000000"])
        vault = CredentialVault(store: secrets, config: config, providers: providers)
        vault.loadStoredKeys()
        let folder = FileManager.default.temporaryDirectory.appending(path: "AfinoPanelDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        history = HistoryStore(fileURL: folder.appending(path: "history.json"))
        session = ImproveSession(
            settings: settings,
            vault: vault,
            library: library,
            composer: composer,
            providers: providers,
            clipboard: SystemClipboard(),
            history: history)
        let session = session
        let history = history
        Task {
            // Oldest first, as they would have been recorded.
            for entry in DemoScript.historyEntries(now: Date()).sorted(by: { $0.date < $1.date }) {
                try? await history.record(entry)
            }
            await session.refreshRecallDrafts()
        }
        Log.logger(.app).notice("Panel demo engine on (failure: \(failure?.rawValue ?? "none", privacy: .public))")
    }

    /// Runs the scripted flags against the panel, once it exists.
    func drive(_ panel: PanelController, arguments: [String]) {
        PanelDemoDriver(arguments: arguments).run(panel)
    }

    /// `base` with the demo's session, settings, vault and history.
    func dependencies(base: PanelDependencies) -> PanelDependencies {
        var dependencies = base
        dependencies.session = session
        dependencies.settings = settings
        dependencies.vault = vault
        dependencies.history = history
        return dependencies
    }

    private static let suiteName = "AfinoPanelDemo"
}

/// Puts the panel into a state from launch arguments, for screenshots (the flags are listed on
/// `PanelDemo`).
struct PanelDemoDriver {
    let arguments: [String]

    private func value(_ flag: String) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    private func has(_ flag: String) -> Bool { arguments.contains(flag) }

    func run(_ panel: PanelController) {
        guard has("--demo-open") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            panel.present()
            let session = panel.session
            if let draft = value("--demo-draft") {
                session.setDraft(draft)
                panel.refreshFromSession()
            }
            if let key = value("--demo-key") {
                try? await Task.sleep(for: .milliseconds(600))
                panel.keyField.setText(key)
                panel.model.setupKeyText = key
                panel.perform(.primary)
                return
            }
            if has("--demo-history") {
                try? await Task.sleep(for: .milliseconds(300))
                panel.perform(.toggleHistory)
                return
            }
            guard has("--demo-submit") else {
                await openMenuIfAsked(panel)
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            panel.perform(.primary)
            if let stop = value("--demo-stop-after").flatMap(Int.init) {
                try? await Task.sleep(for: .milliseconds(stop))
                panel.perform(.stop)
                return
            }
            guard await waitUntilSettled(session) else { return }
            if let instruction = value("--demo-refine") {
                panel.refine(instruction)
                guard await waitUntilSettled(session) else { return }
            }
            if let target = value("--demo-target") {
                session.setTarget(target)
                panel.refreshFromSession()
            }
            if let text = value("--demo-refine-text") {
                panel.refineField.setText(text)
                panel.model.refineText = text
            }
            if has("--demo-expand") {
                panel.perform(.toggleOriginal)
            }
            await openMenuIfAsked(panel)
            if has("--demo-copy-close") {
                try? await Task.sleep(for: .milliseconds(600))
                panel.perform(.copyAndClose)
            }
        }
    }

    private func openMenuIfAsked(_ panel: PanelController) async {
        guard let menu = value("--demo-menu") else { return }
        try? await Task.sleep(for: .milliseconds(500))
        panel.toggleMenu(menu == "target" ? .target : .actions)
    }

    /// Waits for the run in flight to end; false when it never started.
    private func waitUntilSettled(_ session: ImproveSession) async -> Bool {
        for _ in 0..<600 {
            if !session.state.isRunning { return session.state.phase != .composing }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

/// How the demo engine's first run goes wrong.
nonisolated enum DemoFailure: String, Sendable, CaseIterable {
    case invalidKey, missingKey, billing, modelNotFound, rateLimited, rateLimitedNow, overloaded
    case serverError, offline, timedOut, secureConnection, dropped, droppedEarly, refused, truncated
    case empty, malformed, invalidRequest, permissionDenied, contextTooLong

    /// The failure happens after half the text has streamed.
    var happensMidway: Bool {
        self == .dropped || self == .truncated
    }

    func error(for provider: ProviderID) -> EngineFailure? {
        let error: EngineError
        switch self {
        case .invalidKey: error = .invalidKey(provider)
        case .missingKey: error = .missingKey(provider)
        case .billing: error = .billing
        case .modelNotFound: error = .modelNotFound("claude-sonnet-5-5")
        case .rateLimited: error = .rateLimited(retryAfter: .seconds(12))
        case .rateLimitedNow: error = .rateLimited(retryAfter: nil)
        case .overloaded: error = .overloaded
        case .serverError: error = .serverError(status: 500)
        case .offline: error = .offline
        case .timedOut: error = .timedOut(.responseHeaders)
        case .secureConnection: error = .secureConnection
        case .dropped: error = .connectionLost(receivedText: true)
        case .droppedEarly: error = .connectionLost(receivedText: false)
        case .malformed: error = .malformedResponse
        case .invalidRequest: error = .invalidRequest("demo")
        case .permissionDenied: error = .permissionDenied
        case .contextTooLong: error = .contextTooLong
        case .refused, .truncated, .empty: return nil
        }
        return EngineFailure(error, provider: provider, requestID: "req_demo_0001", httpStatus: nil)
    }
}

/// A scripted provider: started → thinking → a pause → the canned prompt in small chunks →
/// finished, or the chosen failure on the first run.
nonisolated final class DemoEngineProvider: PromptEngineProvider, @unchecked Sendable {
    let id: ProviderID
    private let failure: DemoFailure?
    private let retriesFirst: Bool
    private let lock = NSLock()
    private var runCount = 0

    init(id: ProviderID, failure: DemoFailure?, retriesFirst: Bool) {
        self.id = id
        self.failure = failure
        self.retriesFirst = retriesFirst
    }

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        let run = lock.withLock {
            runCount += 1
            return runCount
        }
        let failure = run == 1 ? failure : nil
        let retries = run == 1 && retriesFirst
        let isRevision = request.turns.count > 1
        let text = isRevision ? DemoScript.revision : DemoScript.prompt
        let provider = id
        let model = request.model
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if retries {
                        continuation.yield(.retrying(attempt: 2, after: .seconds(2), reason: .overloaded))
                        try await Task.sleep(for: .seconds(2))
                    }
                    continuation.yield(.started(servedModel: model, requestID: "req_demo_\(run)"))
                    continuation.yield(.thinking)
                    try await Task.sleep(for: .milliseconds(isRevision ? 900 : 1600))
                    if let failure, !failure.happensMidway {
                        switch failure {
                        case .refused:
                            continuation.yield(.finished(.refused(category: nil), usage: nil))
                            continuation.finish()
                            return
                        case .empty:
                            continuation.yield(.finished(.complete, usage: nil))
                            continuation.finish()
                            return
                        default:
                            if let error = failure.error(for: provider) { throw error }
                        }
                    }
                    var sent = 0
                    for chunk in DemoScript.chunks(of: text) {
                        continuation.yield(.textDelta(chunk))
                        sent += chunk.count
                        if let failure, failure.happensMidway, sent > text.count / 2 {
                            if failure == .truncated {
                                continuation.yield(.finished(.truncated, usage: nil))
                                continuation.finish()
                                return
                            }
                            if let error = failure.error(for: provider) { throw error }
                        }
                        try await Task.sleep(for: .milliseconds(24))
                    }
                    continuation.yield(.finished(.complete, usage: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func models(key: APIKey) async throws -> [RemoteModel] {
        try await Task.sleep(for: .milliseconds(900))
        if key.rawValue.count < 12 || key.rawValue.contains("bad") {
            throw EngineFailure(.invalidKey(id), provider: id)
        }
        return []
    }

    func prewarm() async {}
}

/// The demo's canned prompts and the history it starts with.
nonisolated enum DemoScript {
    static let prompt = """
        You are a senior front-end developer who builds small, polished browser games.

        Build a complete Snake game that runs from a single HTML file with no external dependencies. The player steers with the arrow keys or WASD, eats food to grow, and loses on hitting a wall or their own tail.

        Requirements:
        - A 20 × 20 grid drawn on a <canvas>, crisp on Retina displays.
        - The snake speeds up slightly every five pieces of food.
        - Show the current score and the best score, kept in localStorage.
        - Space pauses; Enter restarts after a game over.
        - Keep the code readable: one small module each for game state, rendering and input.

        Style: a calm, dark palette with a single accent colour for the food. No sound.

        Reply with the complete HTML file only, then two sentences on how to change the speed and the grid size.
        """

    static let revision = """
        You are a front-end developer. Build a single-file HTML Snake game on a <canvas> with no dependencies: arrow keys or WASD steer, food makes the snake grow, walls and the tail end the game.

        Show the score and the best score (localStorage). Space pauses, Enter restarts. Calm dark palette, one accent colour.

        Reply with the HTML file only.
        """

    /// Small, uneven chunks, like a model's deltas.
    static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var size = 3
        for character in text {
            current.append(character)
            if current.count >= size {
                chunks.append(current)
                current = ""
                size = size % 7 + 2
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func historyEntries(now: Date) -> [HistoryEntry] {
        let samples: [(String, String, String, TimeInterval)] = [
            ("write a prompt that makes a snake game in one html file", "claude", prompt, 60 * 60 * 26),
            ("summarise this meeting transcript into decisions and owners", "gpt",
             "You are an executive assistant. Summarise the transcript below into the decisions taken and who owns each follow-up…", 60 * 60 * 5),
            ("explícame cómo funciona la caché de prompts y cuándo conviene", "claude",
             "Explica de forma clara y práctica cómo funciona la caché de prompts en los modelos de lenguaje…", 60 * 40),
            ("product photo of a ceramic mug on a linen table, morning light", "gemini",
             "A ceramic mug in matte sage green on a natural linen tablecloth, soft morning light from the left…", 60 * 12),
            ("review this SQL for performance problems", "generic",
             "Review the SQL query below for performance problems. For each issue, explain why it is slow…", 60 * 60 * 24 * 9),
        ]
        return samples.enumerated().map { index, sample in
            HistoryEntry(
                date: now.addingTimeInterval(-sample.3),
                draft: sample.0,
                targetID: sample.1,
                versions: [.init(text: sample.2)] + (index == 0 ? [.init(text: revision, instruction: "Shorter")] : []),
                provider: "anthropic",
                model: "claude-sonnet-5-5")
        }
    }
}
#endif
