import Foundation
import Testing
@testable import PIProviders

/// The bytes each provider puts on the wire, compared with hand-written golden bodies.
struct AnthropicRequestTests {
    private func body(_ request: EngineRequest) throws -> [String: Any] {
        let urlRequest = try AnthropicRequest.urlRequest(for: request, key: testKey, baseURL: AnthropicProvider.defaultBaseURL)
        let data = try #require(urlRequest.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func golden(_ name: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Fixture.data("golden/\(name).json")) as? [String: Any])
    }

    private func request(_ preset: EnginePreset, maxOutputTokens: Int = 16_000, turns: [EngineRequest.Turn]? = nil) -> EngineRequest {
        EngineRequest(
            selection: ModelCatalog.selection(for: preset, provider: .anthropic),
            maxOutputTokens: maxOutputTokens,
            systemBlocks: sampleRequest().systemBlocks,
            turns: turns ?? sampleRequest().turns
        )
    }

    @Test func fastPresetMatchesTheGoldenBody() throws {
        #expect(canonicalJSON(try body(request(.fast))) == canonicalJSON(try golden("anthropic_fast")))
    }

    @Test func balancedPresetMatchesTheGoldenBody() throws {
        #expect(canonicalJSON(try body(request(.balanced))) == canonicalJSON(try golden("anthropic_balanced")))
    }

    @Test func aRefinementMatchesTheGoldenBody() throws {
        let turns: [EngineRequest.Turn] = [
            .user("Improve this: write a haiku about rain"),
            .assistant("Write a haiku about rain."),
            .user("Shorter, and in Spanish."),
        ]
        let sent = try body(request(.quality, maxOutputTokens: 24_000, turns: turns))
        #expect(canonicalJSON(sent) == canonicalJSON(try golden("anthropic_refine")))
    }

    @Test func headersAreTheDocumentedOnes() throws {
        let urlRequest = try AnthropicRequest.urlRequest(for: request(.balanced), key: testKey, baseURL: URL(string: "https://example.test/proxy")!)
        #expect(urlRequest.url?.absoluteString == "https://example.test/proxy/v1/messages")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == testKey.rawValue)
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(urlRequest.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "accept") == "text/event-stream")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(urlRequest.value(forHTTPHeaderField: "authorization") == nil)
    }

    @Test func haikuSendsNoFallbackAndNoBetaHeader() async throws {
        let server = StubServer()
        server.enqueueStream(try Fixture.data("anthropic/ok_text.sse"))
        let provider = makeAnthropic(server)
        _ = await collect(provider.stream(request(.fast), key: testKey))
        let sent = try #require(server.requests.first)
        #expect(sent.header("anthropic-beta") == nil)
        #expect(sent.json["fallbacks"] == nil)
        #expect(sent.json["model"] as? String == "claude-haiku-5-5")
    }

    @Test func aCustomModelSendsNoFallback() throws {
        let sent = try body(request(.custom(model: "claude-opus-4-8", effort: .high)))
        #expect(sent["fallbacks"] == nil)
        #expect(sent["thinking"] == nil)
        #expect((sent["output_config"] as? [String: Any])?["effort"] as? String == "high")
    }

    @Test(arguments: [EnginePreset.fast, .balanced, .quality, .custom(model: "claude-fable-5-2", effort: .max)])
    func samplingParametersAndPrefillAreNeverSent(_ preset: EnginePreset) throws {
        let keys = allKeys(try body(request(preset)))
        for forbidden in ["temperature", "top_p", "top_k", "budget_tokens", "stop_sequences"] {
            #expect(!keys.contains(forbidden), "\(forbidden) was sent")
        }
    }

    @Test func theCacheBreakpointIsOnTheLastSystemBlockOnly() throws {
        var request = sampleRequest()
        request.systemBlocks = ["core", "pack", "preferences"]
        let system = try #require(try body(request)["system"] as? [[String: Any]])
        #expect(system.map { $0["cache_control"] != nil } == [false, false, true])

        request.systemBlocks = ["only"]
        let single = try #require(try body(request)["system"] as? [[String: Any]])
        #expect((single.first?["cache_control"] as? [String: String]) == ["type": "ephemeral"])

        request.systemBlocks = ["", "  "]
        #expect(try body(request)["system"] == nil)
    }

    @Test func aTrailingAssistantTurnIsNotSent() throws {
        var request = sampleRequest()
        request.turns = [.user("draft"), .assistant("partial prefill")]
        let messages = try #require(try body(request)["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "draft"]])
    }

    @Test func effortNoneAndNoEffortSendNoOutputConfig() throws {
        #expect(try body(sampleRequest(effort: Effort.none))["output_config"] == nil)
        #expect(try body(sampleRequest(effort: nil))["output_config"] == nil)
    }

    @Test func aMissingKeyFailsWithoutARequest() async {
        let server = StubServer()
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: APIKey("  \n")))
        #expect(outcome.failure?.error == .missingKey(.anthropic))
        #expect(outcome.events.isEmpty)
        #expect(server.requests.isEmpty)
    }

    @Test func nothingToSendIsAnInvalidRequest() {
        var request = sampleRequest()
        request.turns = [.assistant("only an answer")]
        #expect(throws: EngineFailure.self) { try AnthropicRequest.body(for: request) }
    }
}

struct OpenAIRequestTests {
    private func body(_ request: EngineRequest) throws -> [String: Any] {
        let urlRequest = try OpenAIRequest.urlRequest(for: request, key: testOpenAIKey, baseURL: OpenAIProvider.defaultBaseURL)
        let data = try #require(urlRequest.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func golden(_ name: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Fixture.data("golden/\(name).json")) as? [String: Any])
    }

    private func request(_ preset: EnginePreset, maxOutputTokens: Int = 16_000, turns: [EngineRequest.Turn]? = nil) -> EngineRequest {
        EngineRequest(
            selection: ModelCatalog.selection(for: preset, provider: .openai),
            maxOutputTokens: maxOutputTokens,
            systemBlocks: sampleRequest().systemBlocks,
            turns: turns ?? sampleRequest().turns
        )
    }

    @Test func fastPresetMatchesTheGoldenBody() throws {
        #expect(canonicalJSON(try body(request(.fast))) == canonicalJSON(try golden("openai_fast")))
    }

    @Test func aRefinementMatchesTheGoldenBody() throws {
        let turns: [EngineRequest.Turn] = [
            .user("Improve this: write a haiku about rain"),
            .assistant("Write a haiku about rain."),
            .user("Shorter, and in Spanish."),
        ]
        let sent = try body(request(.quality, maxOutputTokens: 24_000, turns: turns))
        #expect(canonicalJSON(sent) == canonicalJSON(try golden("openai_refine")))
    }

    @Test func theDeveloperItemComesFirstWithEveryBlockJoined() throws {
        var request = sampleRequest(model: "gpt-6.2-sol")
        request.systemBlocks = ["core", "", "pack", "preferences"]
        let input = try #require(try body(request)["input"] as? [[String: Any]])
        #expect(input.first?["role"] as? String == "developer")
        let content = try #require(input.first?["content"] as? [[String: String]])
        #expect(content == [["type": "input_text", "text": "core\n\npack\n\npreferences"]])
        #expect(input.filter { $0["role"] as? String == "developer" }.count == 1)
    }

    @Test func headersAreTheDocumentedOnes() throws {
        let urlRequest = try OpenAIRequest.urlRequest(for: request(.balanced), key: testOpenAIKey, baseURL: OpenAIProvider.defaultBaseURL)
        #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "authorization") == "Bearer \(testOpenAIKey.rawValue)")
        #expect(urlRequest.value(forHTTPHeaderField: "accept") == "text/event-stream")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test(arguments: [EnginePreset.fast, .balanced, .quality])
    func forbiddenFieldsAreNeverSent(_ preset: EnginePreset) throws {
        var request = request(preset)
        request.thinkingDisabled = true
        request.serverSideFallback = true
        let sent = try body(request)
        let keys = allKeys(sent)
        for forbidden in ["instructions", "temperature", "top_p", "previous_response_id", "thinking", "fallbacks"] {
            #expect(!keys.contains(forbidden), "\(forbidden) was sent")
        }
        #expect(sent["store"] as? Bool == false)
        #expect(sent["stream"] as? Bool == true)
    }

    @Test func noEffortSendsNoReasoning() throws {
        #expect(try body(sampleRequest(model: "gpt-6.2-sol", effort: nil))["reasoning"] == nil)
    }

    @Test func aTrailingAssistantTurnIsNotSent() throws {
        var request = sampleRequest(model: "gpt-6.2-sol")
        request.turns = [.user("draft"), .assistant("partial")]
        let input = try #require(try body(request)["input"] as? [[String: Any]])
        #expect(input.map { $0["role"] as? String } == ["developer", "user"])
    }
}
