import Foundation
import Synchronization
import Testing
@testable import PIProviders

/// A clock that never waits: each sleep is recorded and moves time forward at once. `advance`
/// moves it by hand (for the prewarm rate limit).
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol, Hashable {
        var offset: Swift.Duration

        func advanced(by duration: Swift.Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Swift.Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let state = Mutex<(now: Swift.Duration, sleeps: [Swift.Duration])>((.zero, []))

    var now: Instant { Instant(offset: state.withLock { $0.now }) }
    var minimumResolution: Swift.Duration { .zero }
    /// Every wait requested so far, in order.
    var sleeps: [Swift.Duration] { state.withLock { $0.sleeps } }

    func sleep(until deadline: Instant, tolerance: Swift.Duration?) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(deadline.offset - state.now)
            state.now = max(state.now, deadline.offset)
        }
        await Task.yield()
        try Task.checkCancellation()
    }

    func advance(by duration: Swift.Duration) {
        state.withLock { $0.now += duration }
    }
}

/// Fixture files from `Tests/PIProvidersTests/Fixtures`.
enum Fixture {
    static func url(_ path: String) -> URL {
        Bundle.module.resourceURL!.appending(path: "Fixtures/\(path)")
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    static func text(_ path: String) throws -> String {
        String(decoding: try data(path), as: UTF8.self)
    }

    /// Every LF as CRLF (the fixtures are written with LF only).
    static func crlf(_ data: Data) -> Data {
        var result = Data(capacity: data.count + data.count / 20)
        for byte in data {
            if byte == 0x0A { result.append(0x0D) }
            result.append(byte)
        }
        return result
    }

    /// `data` in pieces of `size` bytes; one piece when `size` is nil.
    static func chunks(_ data: Data, size: Int?) -> [Data] {
        guard let size, size > 0, data.count > size else { return [data] }
        return stride(from: 0, to: data.count, by: size).map { start in
            data.subdata(in: start..<min(start + size, data.count))
        }
    }
}

/// How a replayed stream is cut and which line ends it uses.
struct Replay: Sendable, CustomTestStringConvertible {
    var chunkSize: Int?
    var crlf: Bool

    static let all: [Replay] = [1, 7, nil].flatMap { size in [false, true].map { Replay(chunkSize: size, crlf: $0) } }

    func prepare(_ data: Data) -> Data { crlf ? Fixture.crlf(data) : data }

    var testDescription: String { "\(chunkSize.map { "\($0)-byte chunks" } ?? "whole"), \(crlf ? "CRLF" : "LF")" }
}

/// Everything a stream produced: its events and how it ended.
struct StreamOutcome {
    var events: [EngineEvent] = []
    var failure: EngineFailure?
    var otherError: String?

    var text: String {
        events.compactMap { event in
            if case let .textDelta(text) = event { return text }
            return nil
        }.joined()
    }

    var finish: FinishReason? {
        for case let .finished(reason, _) in events { return reason }
        return nil
    }

    var retries: [EngineEvent] {
        events.filter { if case .retrying = $0 { true } else { false } }
    }
}

func collect(_ stream: AsyncThrowingStream<EngineEvent, any Error>) async -> StreamOutcome {
    var outcome = StreamOutcome()
    do {
        for try await event in stream { outcome.events.append(event) }
    } catch let failure as EngineFailure {
        outcome.failure = failure
    } catch {
        outcome.otherError = String(describing: error)
    }
    return outcome
}

let testKey = APIKey("sk-ant-api03-TESTKEY0123456789abcdefghijklmnopqrstuvwxyz-ABCD")
let testOpenAIKey = APIKey("sk-proj-TESTKEY0123456789abcdefghijklmnopqrstuvwxyzWXYZ")

/// Short watchdog timeouts would fire in ordinary tests; these never do.
let relaxedTimeouts = StreamTimeouts.standard

func makeAnthropic(
    _ server: StubServer,
    clock: TestClock = TestClock(),
    policy: RetryPolicy = .standard,
    timeouts: StreamTimeouts = relaxedTimeouts,
    random: Double = 0.5
) -> AnthropicProvider {
    AnthropicProvider(session: server.makeSession(), baseURL: server.baseURL, clock: clock, retryPolicy: policy, timeouts: timeouts, random: { random })
}

func makeOpenAI(
    _ server: StubServer,
    clock: TestClock = TestClock(),
    policy: RetryPolicy = .standard,
    timeouts: StreamTimeouts = relaxedTimeouts,
    random: Double = 0.5
) -> OpenAIProvider {
    OpenAIProvider(session: server.makeSession(), baseURL: server.baseURL, clock: clock, retryPolicy: policy, timeouts: timeouts, random: { random })
}

/// A plain request: two system blocks and one draft.
func sampleRequest(model: String = "claude-sonnet-5-5", effort: Effort? = .low) -> EngineRequest {
    EngineRequest(
        model: model,
        effort: effort,
        maxOutputTokens: 16_000,
        systemBlocks: ["You are the rewriting engine.", "<target_guidance>Be literal.</target_guidance>"],
        turns: [.user("Improve this: write a haiku about rain")]
    )
}

/// The JSON object as sorted, unescaped text, for readable comparisons.
func canonicalJSON(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]) else { return "<not JSON>" }
    return String(decoding: data, as: UTF8.self)
}

/// Every key at any depth of a JSON value.
func allKeys(_ value: Any) -> Set<String> {
    switch value {
    case let object as [String: Any]:
        object.reduce(into: Set(object.keys)) { $0.formUnion(allKeys($1.value)) }
    case let array as [Any]:
        array.reduce(into: Set<String>()) { $0.formUnion(allKeys($1)) }
    default:
        []
    }
}
