import Foundation
import Testing
@testable import PIProviders

/// Fixture streams replayed through a stub host, as the app would see them.
@Suite(.timeLimit(.minutes(1)))
struct AnthropicStreamTests {
    private let headers = ["request-id": "req_anthropic_stream"]

    private func run(_ path: String, replay: Replay = Replay(chunkSize: nil, crlf: false), request: EngineRequest = sampleRequest()) async throws -> StreamOutcome {
        let server = StubServer()
        server.enqueueStream(replay.prepare(try Fixture.data(path)), chunkSize: replay.chunkSize, headers: headers)
        return await collect(makeAnthropic(server, policy: .none).stream(request, key: testKey))
    }

    @Test(arguments: Replay.all)
    func okTextMapsToTheDocumentedEvents(_ replay: Replay) async throws {
        let outcome = try await run("anthropic/ok_text.sse", replay: replay)
        #expect(outcome.failure == nil)
        #expect(outcome.events == [
            .started(servedModel: "claude-sonnet-5-5", requestID: "req_anthropic_stream"),
            .thinking,
            .textDelta("Write a haiku about rain"),
            .textDelta(" falling on a café in 東京 at dusk 🌧️"),
            .textDelta(". Keep the 5–7–5 syllable pattern."),
            .finished(.complete, usage: TokenUsage(inputTokens: 812, outputTokens: 57, cacheReadInputTokens: 640, cacheCreationInputTokens: 0)),
        ])
    }

    @Test(arguments: Replay.all)
    func maxTokensIsTruncated(_ replay: Replay) async throws {
        let outcome = try await run("anthropic/max_tokens.sse", replay: replay)
        #expect(outcome.text == "You are reviewing a pull request. Check each changed file for")
        #expect(outcome.finish == .truncated)
        #expect(outcome.failure == nil)
    }

    @Test(arguments: Replay.all)
    func aRefusalCarriesItsCategory(_ replay: Replay) async throws {
        let outcome = try await run("anthropic/refusal.sse", replay: replay)
        #expect(outcome.text.isEmpty)
        #expect(outcome.events.last == .finished(.refused(category: "cyber"), usage: TokenUsage(inputTokens: 412, outputTokens: 0)))
    }

    @Test func stopDetailsAtTheTopLevelAreReadToo() async throws {
        let stream = """
        event: message_start
        data: {"type":"message_start","message":{"model":"claude-haiku-5-5","usage":{"input_tokens":3}}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"stop_details":{"type":"refusal","category":"bio"},"usage":{"output_tokens":0}}

        event: message_stop
        data: {"type":"message_stop"}


        """
        let server = StubServer()
        server.enqueueStream(Data(stream.utf8))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.finish == .refused(category: "bio"))
    }

    @Test(arguments: Replay.all)
    func aMidStreamFallbackKeepsTheTextAndContinues(_ replay: Replay) async throws {
        let outcome = try await run("anthropic/fallback_midstream.sse", replay: replay)
        #expect(outcome.text == "Rewrite the following request as a clear prompt for a security audit.")
        #expect(outcome.events.first == .started(servedModel: "claude-opus-5-5", requestID: "req_anthropic_stream"))
        #expect(outcome.finish == .complete)
    }

    @Test(arguments: Replay.all)
    func aStreamCutOffAfterTextIsAConnectionLoss(_ replay: Replay) async throws {
        let outcome = try await run("anthropic/cut_off.sse", replay: replay)
        #expect(outcome.text == "Draft a cover letter for a data analyst role")
        #expect(outcome.failure?.error == .connectionLost(receivedText: true))
        #expect(outcome.failure?.requestID == "req_anthropic_stream")
        #expect(outcome.finish == nil)
    }

    @Test func anOverloadedErrorEventWithoutRetriesThrows() async throws {
        let outcome = try await run("anthropic/error_overloaded_midstream.sse")
        #expect(outcome.failure?.error == .overloaded)
        #expect(outcome.failure?.provider == .anthropic)
        #expect(outcome.failure?.requestID == "req_anthropic_stream")
    }

    @Test func aMultiByteCharacterSplitBetweenChunksArrivesWhole() async throws {
        let data = try Fixture.data("anthropic/ok_text.sse")
        let marker = Data("東".utf8)
        let index = try #require(data.firstRange(of: marker)).lowerBound + 1
        let server = StubServer()
        server.enqueue([
            .head(status: 200, headers: ["Content-Type": "text/event-stream"]),
            .chunk(data.subdata(in: 0..<index)),
            .delay(.milliseconds(20)),
            .chunk(data.subdata(in: index..<data.count)),
            .finish,
        ])
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.text == "Write a haiku about rain falling on a café in 東京 at dusk 🌧️. Keep the 5–7–5 syllable pattern.")
    }

    @Test func aSuccessThatIsNotAnEventStreamIsMalformed() async {
        let server = StubServer()
        server.enqueueJSON(status: 200, body: Data(#"{"id":"msg_1","content":[]}"#.utf8), headers: headers)
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure?.error == .malformedResponse)
        #expect(outcome.failure?.requestID == "req_anthropic_stream")
        #expect(server.requests.count == 1)
    }

    @Test func dataThatIsNotJSONIsMalformed() async {
        let server = StubServer()
        server.enqueueStream(Data("event: message_start\ndata: {not json\n\n".utf8))
        let outcome = await collect(makeAnthropic(server, policy: .none).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure?.error == .malformedResponse)
    }

    @Test func unknownEventsAndDoneMarkersAreIgnored() async throws {
        let extra = Data("event: future_event\ndata: {\"type\":\"future_event\",\"x\":1}\n\ndata: [DONE]\n\n".utf8)
        let server = StubServer()
        server.enqueueStream(extra + (try Fixture.data("anthropic/ok_text.sse")))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.finish == .complete)
        #expect(outcome.failure == nil)
    }

    @Test func droppingTheStreamCancelsTheRequest() async throws {
        let server = StubServer()
        let data = try Fixture.data("anthropic/ok_text.sse")
        server.enqueue([
            .head(status: 200, headers: ["Content-Type": "text/event-stream"]),
            .chunk(data.prefix(400)),
            .delay(.seconds(30)),
            .chunk(data.dropFirst(400)),
            .finish,
        ])
        let started = ContinuousClock.now
        let stream = makeAnthropic(server).stream(sampleRequest(), key: testKey)
        let consumer = Task {
            var events: [EngineEvent] = []
            for try await event in stream {
                events.append(event)
            }
            return events
        }
        try await Task.sleep(for: .milliseconds(200))
        consumer.cancel()
        _ = try? await consumer.value
        #expect(started.duration(to: .now) < .seconds(10))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct OpenAIStreamTests {
    private let headers = ["x-request-id": "req_openai_stream"]

    private func run(_ path: String, replay: Replay = Replay(chunkSize: nil, crlf: false)) async throws -> StreamOutcome {
        let server = StubServer()
        server.enqueueStream(replay.prepare(try Fixture.data(path)), chunkSize: replay.chunkSize, headers: headers)
        return await collect(makeOpenAI(server, policy: .none).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
    }

    @Test(arguments: Replay.all)
    func okTextMapsToTheDocumentedEvents(_ replay: Replay) async throws {
        let outcome = try await run("openai/ok_text.sse", replay: replay)
        #expect(outcome.failure == nil)
        #expect(outcome.events == [
            .started(servedModel: "gpt-6.2-sol", requestID: "req_openai_stream"),
            .thinking,
            .textDelta("Write a haiku about rain"),
            .textDelta(" falling on a café in 東京 at dusk 🌧️"),
            .textDelta(". Keep the 5–7–5 syllable pattern."),
            .finished(.complete, usage: TokenUsage(inputTokens: 812, outputTokens: 57, cacheReadInputTokens: 640, reasoningTokens: 12)),
        ])
    }

    @Test(arguments: Replay.all)
    func incompleteAtTheOutputLimitIsTruncated(_ replay: Replay) async throws {
        let outcome = try await run("openai/incomplete_max_output_tokens.sse", replay: replay)
        #expect(outcome.text == "You are reviewing a pull request. Check each changed file for")
        #expect(outcome.finish == .truncated)
    }

    @Test func incompleteByContentFilterIsARefusal() async {
        let stream = """
        data: {"type":"response.created","response":{"model":"gpt-6.2-sol"}}

        data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"content_filter"}}}


        """
        let server = StubServer()
        server.enqueueStream(Data(stream.utf8))
        let outcome = await collect(makeOpenAI(server).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(outcome.finish == .refused(category: "content_filter"))
    }

    @Test(arguments: Replay.all)
    func aRefusalIsReportedAndItsTextIsNotTheAnswer(_ replay: Replay) async throws {
        let outcome = try await run("openai/refusal.sse", replay: replay)
        #expect(outcome.text.isEmpty)
        #expect(outcome.finish == .refused(category: nil))
    }

    @Test func aRefusalOnlyInTheCompletedOutputIsReportedToo() async {
        let stream = """
        data: {"type":"response.created","response":{"model":"gpt-6.2-sol"}}

        data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No."}]}]}}


        """
        let server = StubServer()
        server.enqueueStream(Data(stream.utf8))
        let outcome = await collect(makeOpenAI(server).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(outcome.finish == .refused(category: nil))
    }

    @Test(arguments: Replay.all)
    func aFailedResponseThrows(_ replay: Replay) async throws {
        let outcome = try await run("openai/failed.sse", replay: replay)
        #expect(outcome.failure?.error == .serverError(status: 500))
        #expect(outcome.failure?.requestID == "req_openai_stream")
        #expect(outcome.events == [.started(servedModel: "gpt-6.2-sol", requestID: "req_openai_stream")])
    }

    @Test(arguments: Replay.all)
    func anErrorEventThrowsARedactedMessage(_ replay: Replay) async throws {
        let outcome = try await run("openai/error_event.sse", replay: replay)
        guard case let .invalidRequest(message)? = outcome.failure?.error else {
            Issue.record("Expected invalidRequest, got \(String(describing: outcome.failure))")
            return
        }
        #expect(message.hasPrefix("Invalid prompt:"))
        #expect(!message.contains(testOpenAIKey.rawValue))
        #expect(!message.contains("sk-"))
    }
}
