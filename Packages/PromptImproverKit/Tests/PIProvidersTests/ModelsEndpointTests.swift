import Foundation
import Testing
@testable import PIProviders

@Suite(.timeLimit(.minutes(1)))
struct ModelsEndpointTests {
    @Test func anthropicFollowsEveryPage() async throws {
        let server = StubServer()
        let first = """
        {"data":[
          {"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","max_tokens":128000,
           "capabilities":{"effort":{"supported":true,"low":{"supported":true},"medium":{"supported":true},"high":{"supported":true},"xhigh":{"supported":true},"max":{"supported":true}},
                           "thinking":{"supported":true,"types":{"disabled":{"supported":false}}}}},
          {"type":"model","id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5","max_tokens":0,"capabilities":null}
        ],"has_more":true,"first_id":"claude-opus-5-5","last_id":"claude-sonnet-5-5"}
        """
        let second = """
        {"data":[{"type":"model","id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5"}],"has_more":false,"first_id":"claude-haiku-5-5","last_id":"claude-haiku-5-5"}
        """
        server.enqueueJSON(status: 200, body: Data(first.utf8))
        server.enqueueJSON(status: 200, body: Data(second.utf8))
        let models = try await makeAnthropic(server).models(key: testKey)
        #expect(models.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
        #expect(models[0] == RemoteModel(id: "claude-opus-5-5", displayName: "Claude Opus 5.5", maxOutputTokens: 128_000, supportedEfforts: [.low, .medium, .high, .xhigh, .max], supportsThinkingDisabled: false))
        #expect(models[1].maxOutputTokens == nil)
        #expect(models[1].supportedEfforts == nil)

        let requests = server.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "GET" && $0.url.path() == "/v1/models" })
        #expect(requests.allSatisfy { $0.header("x-api-key") == testKey.rawValue && $0.header("anthropic-version") == "2026-10-21" })
        #expect(requests[0].url.query()?.contains("after_id") == false)
        #expect(requests[1].url.query()?.contains("after_id=claude-sonnet-5-5") == true)
    }

    @Test func anthropicBadKeyIsInvalidKey() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 401, body: try Fixture.data("anthropic/error_401.json"), headers: ["request-id": "req_models"])
        await #expect(throws: EngineFailure(.invalidKey(.anthropic), provider: .anthropic, requestID: "req_models", httpStatus: 401)) {
            try await makeAnthropic(server).models(key: testKey)
        }
    }

    @Test func openAIKeepsOnlyGPTTextModels() async throws {
        let ids = [
            "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-4.1",
            "gpt-6-audio-preview", "gpt-6-realtime", "gpt-image-2", "gpt-6-mini-tts", "gpt-6-transcribe",
            "text-embedding-3-large", "o4-mini", "chatgpt-4o-latest", "gpt-oss-120b", "dall-e-3", "gpt-6.2-sol-embedding",
        ]
        let body = #"{"object":"list","data":["# + ids.map { #"{"id":"\#($0)","object":"model","created":1,"owned_by":"openai"}"# }.joined(separator: ",") + "]}"
        let server = StubServer()
        server.enqueueJSON(status: 200, body: Data(body.utf8))
        let models = try await makeOpenAI(server).models(key: testOpenAIKey)
        #expect(models.map(\.id) == ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-4.1"])
        #expect(server.requests.first?.header("authorization") == "Bearer \(testOpenAIKey.rawValue)")
    }

    @Test func openAIBadKeyIsInvalidKeyAndNeverEchoesIt() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 401, body: try Fixture.data("openai/error_401.json"), headers: ["x-request-id": "req_oai_401"])
        do {
            _ = try await makeOpenAI(server).models(key: testOpenAIKey)
            Issue.record("Expected a failure")
        } catch {
            let failure = try #require(error as? EngineFailure)
            #expect(failure.error == .invalidKey(.openai))
            #expect(failure.requestID == "req_oai_401")
            for text in [String(describing: error), String(reflecting: error), "\(failure)"] {
                #expect(!text.contains(testOpenAIKey.rawValue))
                #expect(!text.contains("sk-"))
            }
        }
    }

    @Test(arguments: [ProviderID.anthropic, .openai])
    func aMissingKeySendsNothing(_ provider: ProviderID) async {
        let server = StubServer()
        let engine: any PromptEngineProvider = provider == .anthropic ? makeAnthropic(server) : makeOpenAI(server)
        await #expect(throws: EngineFailure(.missingKey(provider), provider: provider)) {
            try await engine.models(key: APIKey(""))
        }
        #expect(server.requests.isEmpty)
    }

    @Test func aListThatIsNotAListIsMalformed() async {
        let server = StubServer()
        server.enqueueJSON(status: 200, body: Data(#"{"unexpected":true}"#.utf8))
        await #expect(throws: EngineFailure(.malformedResponse, provider: .openai)) {
            try await makeOpenAI(server).models(key: testOpenAIKey)
        }
    }
}
