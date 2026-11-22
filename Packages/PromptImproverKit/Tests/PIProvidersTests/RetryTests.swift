import Foundation
import Testing
@testable import PIProviders

struct RetryPolicyTests {
    private let policy = RetryPolicy.standard
    private let overloaded = AttemptFailure(error: .overloaded, retryable: true)

    @Test func backsOffHalfASecondThenOneAndAHalf() {
        #expect(policy.decision(after: overloaded, attempt: 1, receivedText: false, random: 0.5) == .retry(after: .milliseconds(500), reason: .overloaded))
        #expect(policy.decision(after: overloaded, attempt: 2, receivedText: false, random: 0.5) == .retry(after: .milliseconds(1_500), reason: .overloaded))
    }

    @Test func jitterStaysWithinAQuarter() {
        #expect(policy.decision(after: overloaded, attempt: 1, receivedText: false, random: 0) == .retry(after: .milliseconds(375), reason: .overloaded))
        #expect(policy.decision(after: overloaded, attempt: 1, receivedText: false, random: 1) == .retry(after: .milliseconds(625), reason: .overloaded))
        #expect(policy.decision(after: overloaded, attempt: 2, receivedText: false, random: 0) == .retry(after: .milliseconds(1_125), reason: .overloaded))
        #expect(policy.decision(after: overloaded, attempt: 2, receivedText: false, random: 1) == .retry(after: .milliseconds(1_875), reason: .overloaded))
    }

    @Test func threeAttemptsInAll() {
        #expect(policy.decision(after: overloaded, attempt: 3, receivedText: false, random: 0.5) == .giveUp)
    }

    @Test func neverOnceTextWasEmitted() {
        #expect(policy.decision(after: overloaded, attempt: 1, receivedText: true, random: 0.5) == .giveUp)
    }

    @Test func notRetryableMeansGiveUp() {
        let billing = AttemptFailure(error: .billing, retryable: false)
        #expect(policy.decision(after: billing, attempt: 1, receivedText: false, random: 0.5) == .giveUp)
    }

    @Test func aRequestedWaitIsHonouredExactly() {
        let limited = AttemptFailure(error: .rateLimited(retryAfter: .seconds(7)), retryable: true, retryAfter: .seconds(7))
        #expect(policy.decision(after: limited, attempt: 1, receivedText: false, random: 0) == .retry(after: .seconds(7), reason: .rateLimited))
        let atLimit = AttemptFailure(error: .rateLimited(retryAfter: .seconds(20)), retryable: true, retryAfter: .seconds(20))
        #expect(policy.decision(after: atLimit, attempt: 2, receivedText: false, random: 0) == .retry(after: .seconds(20), reason: .rateLimited))
    }

    @Test func aLongRequestedWaitFailsAtOnce() {
        let limited = AttemptFailure(error: .rateLimited(retryAfter: .seconds(21)), retryable: true, retryAfter: .seconds(21))
        #expect(policy.decision(after: limited, attempt: 1, receivedText: false, random: 0.5) == .giveUp)
    }

    @Test func shouldRetryOverridesTheTable() {
        var forced = AttemptFailure(error: .invalidRequest("x"), retryable: false, shouldRetry: true)
        #expect(policy.decision(after: forced, attempt: 1, receivedText: false, random: 0.5) == .retry(after: .milliseconds(500), reason: .requestedByServer))
        forced.shouldRetry = false
        #expect(policy.decision(after: forced, attempt: 1, receivedText: false, random: 0.5) == .giveUp)
        let refused = AttemptFailure(error: .overloaded, retryable: true, shouldRetry: false)
        #expect(policy.decision(after: refused, attempt: 1, receivedText: false, random: 0.5) == .giveUp)
    }

    @Test func cancellationIsNeverRetried() {
        let cancelled = AttemptFailure(error: .cancelled, retryable: true, shouldRetry: true)
        #expect(policy.decision(after: cancelled, attempt: 1, receivedText: false, random: 0.5) == .giveUp)
    }

    @Test func reasonsFollowTheError() {
        #expect(RetryPolicy.reason(for: AttemptFailure(error: .serverError(status: 502))) == .serverError(status: 502))
        #expect(RetryPolicy.reason(for: AttemptFailure(error: .timedOut(.responseHeaders))) == .timedOut)
        #expect(RetryPolicy.reason(for: AttemptFailure(error: .connectionLost(receivedText: false))) == .network)
        #expect(RetryPolicy.reason(for: AttemptFailure(error: .offline)) == .network)
    }

    @Test func retryAfterHeadersParse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(RetryAfter.parse(milliseconds: "1500", header: "9", now: now) == .milliseconds(1_500))
        #expect(RetryAfter.parse(milliseconds: nil, header: "9", now: now) == .seconds(9))
        #expect(RetryAfter.parse(milliseconds: nil, header: "2.5", now: now) == .seconds(2.5))
        #expect(RetryAfter.parse(milliseconds: "garbage", header: nil, now: now) == nil)
        let date = try #require(RetryAfter.httpDate("Tue, 14 Nov 2023 22:13:32 GMT"))
        #expect(RetryAfter.parse(milliseconds: nil, header: "Tue, 14 Nov 2023 22:13:32 GMT", now: date.addingTimeInterval(-12)) == .seconds(12))
        #expect(RetryAfter.parse(milliseconds: nil, header: "Tue, 14 Nov 2023 22:13:32 GMT", now: date.addingTimeInterval(60)) == .zero)
        #expect(RetryAfter.httpDate("Tuesday, 14-Nov-23 22:13:32 GMT") == date)
        #expect(RetryAfter.httpDate("Tue Nov 14 22:13:32 2023") == date)
    }
}

/// Retries through the stub host, with a clock that records the waits instead of waiting.
@Suite(.timeLimit(.minutes(1)))
struct RetryIntegrationTests {
    @Test func overloadedTwiceThenAnswers() async throws {
        let server = StubServer()
        let body = try Fixture.data("anthropic/error_529.json")
        server.enqueueJSON(status: 529, body: body)
        server.enqueueJSON(status: 529, body: body)
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let clock = TestClock()
        let outcome = await collect(makeAnthropic(server, clock: clock, random: 0.5).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure == nil)
        #expect(outcome.retries == [
            .retrying(attempt: 2, after: .milliseconds(500), reason: .overloaded),
            .retrying(attempt: 3, after: .milliseconds(1_500), reason: .overloaded),
        ])
        #expect(clock.sleeps == [.milliseconds(500), .milliseconds(1_500)])
        #expect(server.requests.count == 3)
        #expect(outcome.finish == .complete)
        #expect(outcome.events.firstIndex(of: .retrying(attempt: 3, after: .milliseconds(1_500), reason: .overloaded))! < outcome.events.firstIndex { if case .started = $0 { true } else { false } }!)
    }

    @Test func givesUpAfterThreeAttempts() async throws {
        let server = StubServer()
        for _ in 0..<4 { server.enqueueJSON(status: 503, body: try Fixture.data("openai/error_503.json")) }
        let clock = TestClock()
        let outcome = await collect(makeOpenAI(server, clock: clock, random: 0).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(outcome.failure?.error == .overloaded)
        #expect(outcome.failure?.httpStatus == 503)
        #expect(outcome.retries.count == 2)
        #expect(clock.sleeps == [.milliseconds(375), .milliseconds(1_125)])
        #expect(server.requests.count == 3)
    }

    @Test func retryAfterIsHonoured() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 429, body: try Fixture.data("anthropic/error_429_retry_after.json"), headers: ["retry-after": "3"])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let clock = TestClock()
        let outcome = await collect(makeAnthropic(server, clock: clock).stream(sampleRequest(), key: testKey))
        #expect(outcome.retries == [.retrying(attempt: 2, after: .seconds(3), reason: .rateLimited)])
        #expect(clock.sleeps == [.seconds(3)])
        #expect(outcome.finish == .complete)
    }

    @Test func retryAfterInMillisecondsWins() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 429, body: try Fixture.data("openai/error_429_rate.json"), headers: ["retry-after-ms": "120", "retry-after": "1"])
        server.enqueueStream(try Fixture.data("openai/ok_text.sse"))
        let clock = TestClock()
        let outcome = await collect(makeOpenAI(server, clock: clock).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(clock.sleeps == [.milliseconds(120)])
        #expect(outcome.finish == .complete)
    }

    @Test func aLongRetryAfterFailsFast() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 429, body: try Fixture.data("anthropic/error_429_retry_after.json"), headers: ["retry-after": "60", "request-id": "req_long"])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let clock = TestClock()
        let outcome = await collect(makeAnthropic(server, clock: clock).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure == EngineFailure(.rateLimited(retryAfter: .seconds(60)), provider: .anthropic, requestID: "req_long", httpStatus: 429))
        #expect(outcome.retries.isEmpty)
        #expect(clock.sleeps.isEmpty)
        #expect(server.requests.count == 1)
    }

    @Test func shouldRetryFalseStopsARetryableError() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 529, body: try Fixture.data("anthropic/error_529.json"), headers: ["x-should-retry": "false"])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure?.error == .overloaded)
        #expect(server.requests.count == 1)
    }

    @Test func shouldRetryTrueRetriesAnythingElse() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 400, body: try Fixture.data("anthropic/error_400.json"), headers: ["x-should-retry": "true"])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let clock = TestClock()
        let outcome = await collect(makeAnthropic(server, clock: clock).stream(sampleRequest(), key: testKey))
        #expect(outcome.retries == [.retrying(attempt: 2, after: .milliseconds(500), reason: .requestedByServer)])
        #expect(outcome.finish == .complete)
    }

    @Test(arguments: [
        ("anthropic/error_401.json", 401), ("anthropic/error_402.json", 402), ("anthropic/error_404.json", 404),
        ("anthropic/error_400.json", 400), ("anthropic/error_429_spend_cap.json", 429),
    ])
    func clientErrorsAreNeverRetried(_ fixture: String, _ status: Int) async throws {
        let server = StubServer()
        server.enqueueJSON(status: status, body: try Fixture.data(fixture))
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure != nil)
        #expect(outcome.retries.isEmpty)
        #expect(server.requests.count == 1)
    }

    @Test func aMidStreamOverloadBeforeAnyTextIsRetried() async throws {
        let server = StubServer()
        server.enqueueStream(try Fixture.data("anthropic/error_overloaded_midstream.sse"))
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.retries == [.retrying(attempt: 2, after: .milliseconds(500), reason: .overloaded)])
        #expect(outcome.events.filter { if case .started = $0 { true } else { false } }.count == 2)
        #expect(outcome.finish == .complete)
        #expect(server.requests.count == 2)
    }

    @Test func aMidStreamOverloadAfterTextIsNotRetried() async throws {
        let stream = """
        event: message_start
        data: {"type":"message_start","message":{"model":"claude-sonnet-5-5"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}

        event: error
        data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}


        """
        let server = StubServer()
        server.enqueueStream(Data(stream.utf8))
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.text == "Partial")
        #expect(outcome.failure?.error == .overloaded)
        #expect(outcome.retries.isEmpty)
        #expect(server.requests.count == 1)
    }

    @Test func aFailedOpenAIResponseBeforeTextIsRetried() async throws {
        let server = StubServer()
        server.enqueueStream(try Fixture.data("openai/failed.sse"))
        server.enqueueStream(try Fixture.data("openai/ok_text.sse"))
        let outcome = await collect(makeOpenAI(server).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(outcome.retries == [.retrying(attempt: 2, after: .milliseconds(500), reason: .serverError(status: 500))])
        #expect(outcome.finish == .complete)
    }

    @Test(arguments: [URLError.Code.networkConnectionLost, .cannotConnectToHost, .timedOut])
    func transientTransportErrorsAreRetried(_ code: URLError.Code) async throws {
        let server = StubServer()
        server.enqueue([.fail(code)])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.retries.count == 1)
        #expect(outcome.finish == .complete)
    }

    @Test func aDroppedConnectionAfterTextIsNotRetried() async throws {
        let data = try Fixture.data("anthropic/ok_text.sse")
        let cut = try #require(data.firstRange(of: Data("falling".utf8))).lowerBound
        let server = StubServer()
        server.enqueue([.head(status: 200, headers: ["Content-Type": "text/event-stream"]), .chunk(data.prefix(cut)), .delay(.milliseconds(20)), .fail(.networkConnectionLost)])
        server.enqueueStream(data)
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.text == "Write a haiku about rain")
        #expect(outcome.failure?.error == .connectionLost(receivedText: true))
        #expect(server.requests.count == 1)
    }

    @Test func cancellingDuringABackOffStopsAtOnce() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 529, body: try Fixture.data("anthropic/error_529.json"))
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let slow = RetryPolicy(maxAttempts: 3, backoff: [.seconds(30)], jitter: 0, maxRetryAfter: .seconds(20))
        let provider = AnthropicProvider(session: server.makeSession(), baseURL: server.baseURL, retryPolicy: slow)
        let stream = provider.stream(sampleRequest(), key: testKey)
        let started = ContinuousClock.now
        let consumer = Task {
            for try await event in stream {
                if case .retrying = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        _ = await consumer.result
        #expect(started.duration(to: .now) < .seconds(10))
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.count == 1)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct WatchdogTests {
    private func timeouts(headers: Duration = .seconds(20), idle: Duration = .seconds(300)) -> StreamTimeouts {
        StreamTimeouts(responseHeaders: headers, idle: idle, models: .seconds(30), prewarm: .seconds(3))
    }

    @Test func noResponseHeadInTimeTimesOut() async {
        let server = StubServer()
        server.enqueue([.delay(.seconds(30)), .head(status: 200, headers: ["Content-Type": "text/event-stream"]), .finish])
        let provider = makeAnthropic(server, policy: .none, timeouts: timeouts(headers: .milliseconds(200)))
        let started = ContinuousClock.now
        let outcome = await collect(provider.stream(sampleRequest(), key: testKey))
        #expect(outcome.failure?.error == .timedOut(.responseHeaders))
        #expect(started.duration(to: .now) < .seconds(10))
    }

    @Test func theResponseHeadWatchdogIsRetried() async throws {
        let server = StubServer()
        server.enqueue([.delay(.seconds(30)), .finish])
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let provider = makeAnthropic(server, timeouts: timeouts(headers: .milliseconds(200)))
        let outcome = await collect(provider.stream(sampleRequest(), key: testKey))
        #expect(outcome.retries == [.retrying(attempt: 2, after: .milliseconds(500), reason: .timedOut)])
        #expect(outcome.finish == .complete)
        #expect(server.requests.count == 2)
    }

    @Test func silenceAfterTheStartTimesOutAndIsNotRetried() async throws {
        let data = try Fixture.data("anthropic/ok_text.sse")
        let server = StubServer()
        server.enqueue([
            .head(status: 200, headers: ["Content-Type": "text/event-stream"]),
            .chunk(data.prefix(600)),
            .delay(.seconds(30)),
            .chunk(data.dropFirst(600)),
            .finish,
        ])
        server.enqueueStream(data)
        let provider = makeAnthropic(server, timeouts: timeouts(idle: .milliseconds(300)))
        let started = ContinuousClock.now
        let outcome = await collect(provider.stream(sampleRequest(), key: testKey))
        #expect(outcome.failure?.error == .timedOut(.idle))
        #expect(outcome.retries.isEmpty)
        #expect(server.requests.count == 1)
        #expect(started.duration(to: .now) < .seconds(10))
    }

    @Test func silenceShorterThanTheIdleLimitIsFine() async throws {
        let data = try Fixture.data("anthropic/ok_text.sse")
        let server = StubServer()
        server.enqueue([
            .head(status: 200, headers: ["Content-Type": "text/event-stream"]),
            .chunk(data.prefix(600)),
            .delay(.milliseconds(400)),
            .chunk(data.dropFirst(600)),
            .finish,
        ])
        let provider = makeAnthropic(server, timeouts: timeouts(headers: .milliseconds(300), idle: .seconds(3)))
        let outcome = await collect(provider.stream(sampleRequest(), key: testKey))
        #expect(outcome.failure == nil)
        #expect(outcome.finish == .complete)
    }
}
