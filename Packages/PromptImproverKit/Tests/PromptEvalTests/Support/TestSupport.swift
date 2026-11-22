import Foundation
import PIPrompts
import PIProviders
import Synchronization
@testable import PromptEval

/// What a scripted provider answers to one request.
struct ScriptedReply: Sendable {
    var events: [EngineEvent]
    /// Thrown after the events, instead of finishing normally.
    var failure: EngineFailure?

    /// A normal answer: started, the text in a few deltas, finished.
    static func text(_ text: String, finish: FinishReason = .complete, usage: TokenUsage? = ScriptedReply.defaultUsage) -> ScriptedReply {
        var events: [EngineEvent] = [.started(servedModel: "scripted-model", requestID: "req_scripted")]
        var rest = Substring(text)
        while !rest.isEmpty {
            events.append(.textDelta(String(rest.prefix(40))))
            rest = rest.dropFirst(40)
        }
        events.append(.finished(finish, usage: usage))
        return ScriptedReply(events: events)
    }

    static func failing(_ failure: EngineFailure, after events: [EngineEvent] = []) -> ScriptedReply {
        ScriptedReply(events: events, failure: failure)
    }

    static let defaultUsage = TokenUsage(inputTokens: 1_200, outputTokens: 150, cacheReadInputTokens: 2_000, cacheCreationInputTokens: 0)
}

/// An in-process provider: answers each request with a scripted reply and records what it got.
final class ScriptedProvider: PromptEngineProvider, Sendable {
    let id: ProviderID
    private let respond: @Sendable (EngineRequest) -> ScriptedReply
    private let received = Mutex<[EngineRequest]>([])
    private let keysSeen = Mutex<[String]>([])

    init(id: ProviderID, respond: @escaping @Sendable (EngineRequest) -> ScriptedReply) {
        self.id = id
        self.respond = respond
    }

    var requests: [EngineRequest] { received.withLock { $0 } }
    var keys: [String] { keysSeen.withLock { $0 } }

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        received.withLock { $0.append(request) }
        keysSeen.withLock { $0.append(key.rawValue) }
        let reply = respond(request)
        return AsyncThrowingStream { continuation in
            for event in reply.events {
                continuation.yield(event)
            }
            if let failure = reply.failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }

    func models(key: APIKey) async throws -> [RemoteModel] { [] }

    func prewarm() async {}
}

/// A console that records what was written and answers prompts from a script.
final class TestConsole: EvalConsole, Sendable {
    private let state: Mutex<(output: [String], errors: [String], input: [String])>

    init(input: [String] = []) {
        state = Mutex(([], [], input))
    }

    var output: String { state.withLock { $0.output.joined(separator: "\n") } }
    var errors: String { state.withLock { $0.errors.joined(separator: "\n") } }

    func write(_ line: String) { state.withLock { $0.output.append(line) } }
    func writeError(_ line: String) { state.withLock { $0.errors.append(line) } }
    func readLine() -> String? {
        state.withLock { $0.input.isEmpty ? nil : $0.input.removeFirst() }
    }
}

/// The bundled resources, loaded once.
enum Shipped {
    static let fixtures: FixtureLibrary = {
        do { return try FixtureLibrary.bundled() } catch { fatalError("fixtures: \(error)") }
    }()

    static let packs: TargetPackLibrary = {
        do { return try TargetPackLibrary.bundled() } catch { fatalError("packs: \(error)") }
    }()

    static let composer: PromptComposer = {
        do { return try PromptComposer.bundled() } catch { fatalError("composer: \(error)") }
    }()

    static func fixture(_ id: String) -> Fixture {
        guard let fixture = fixtures.fixture(withID: id) else { fatalError("no fixture \(id)") }
        return fixture
    }
}

/// The draft inside the RUN message, as the scripted engine sees it.
func draft(in request: EngineRequest) -> String? {
    guard case .user(let run)? = request.turns.first,
          let open = run.range(of: "\">\n"),
          let close = run.range(of: "\n</draft id=\"", options: .backwards)
    else { return nil }
    return String(run[open.upperBound..<close.lowerBound])
}

/// Whether the request is the rubric judge's rather than the engine's.
func isJudgeRequest(_ request: EngineRequest) -> Bool {
    request.systemBlocks == [RubricJudge.systemPrompt]
}

/// A judge reply with every criterion passing and the given score.
func judgeReply(overall: Int = 5, failing: Set<String> = []) -> String {
    let criteria = RubricJudge.criteria.map { name in
        "\"\(name)\": {\"pass\": \(!failing.contains(name)), \"reason\": \"scripted\"}"
    }
    return "{" + criteria.joined(separator: ", ") + ", \"overall\": \(overall)}"
}

/// A fresh, empty folder under the temporary directory.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "prompt-eval-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
