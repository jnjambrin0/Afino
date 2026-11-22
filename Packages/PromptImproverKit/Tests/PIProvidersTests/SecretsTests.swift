import Foundation
import Testing
@testable import PIProviders

struct RedactorTests {
    @Test(arguments: [
        "sk-ant-api03-AbCdEf0123456789_ghIJkl-MNopqr",
        "sk-ant-admin01-AbCdEf0123456789",
        "sk-proj-AbCdEf0123456789ghIJklMNopqrST",
        "sk-svcacct-AbCdEf0123456789",
        "sk-proj-********************abcd",
        "sk-AbCdEf0123456789ghIJkl",
    ])
    func keysOfEveryShapeAreRemoved(_ key: String) {
        let scrubbed = Redactor.scrub("Incorrect API key provided: \(key). Try again.")
        #expect(!scrubbed.contains(key))
        #expect(scrubbed == "Incorrect API key provided: [redacted]. Try again.")
    }

    @Test func bearerTokensAreRemoved() {
        let scrubbed = Redactor.scrub("header was Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig==, rejected")
        #expect(scrubbed == "header was Authorization: Bearer [redacted], rejected")
    }

    @Test func knownSecretsAreRemovedWhateverTheirShape() {
        let secret = "custom-proxy-token-0123456789"
        #expect(Redactor.scrub("token \(secret) expired", knownSecrets: [secret]) == "token [redacted] expired")
        #expect(Redactor.scrub("a short ab stays", knownSecrets: ["ab"]) == "a short ab stays")
    }

    @Test func ordinaryTextIsLeftAlone() {
        let text = "A task-based, risk-free, disk-heavy plan: ask-me-anything sk- and sk-1 stay."
        #expect(Redactor.scrub(text) == text)
    }

    @Test func providerMessagesAreScrubbedBeforeTheyBecomeErrors() {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"x-api-key \#(testKey.rawValue) is not valid for this workspace"}}"#.utf8)
        let failure = AnthropicErrors.failure(for: HTTPErrorResponse(head: ResponseHead(status: 400, headers: [:], requestIDHeader: "request-id"), body: body), model: "m", knownSecrets: [testKey.rawValue])
        #expect(failure.error == .invalidRequest("x-api-key [redacted] is not valid for this workspace"))
    }

    @Test func longMessagesAreShortened() {
        let message = Redactor.scrubbedMessage(String(repeating: "a", count: 1_000), knownSecrets: [])
        #expect(message.count == 301)
        #expect(message.hasSuffix("…"))
    }

    @Test func anEchoedKeyNeverSurfacesFromAStreamError() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 401, body: try Fixture.data("openai/error_401.json"))
        let stream = makeOpenAI(server).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey)
        do {
            for try await _ in stream {}
            Issue.record("Expected a failure")
        } catch {
            #expect((error as? EngineFailure)?.error == .invalidKey(.openai))
            for text in [String(describing: error), String(reflecting: error), "\(error)", error.localizedDescription] {
                #expect(!text.contains(testOpenAIKey.rawValue))
                #expect(!text.contains("TESTKEY"))
            }
        }
    }
}

struct APIKeyTests {
    private let key = APIKey("  sk-ant-api03-SECRETSECRETSECRET-wxyz\n")

    @Test func whitespaceIsTrimmed() {
        #expect(key.rawValue == "sk-ant-api03-SECRETSECRETSECRET-wxyz")
        #expect(APIKey(" \n").isEmpty)
    }

    @Test func everyWayOfPrintingItIsMasked() {
        var dumped = ""
        dump(key, to: &dumped)
        let renderings = [
            key.description, key.debugDescription, "\(key)", String(describing: key), String(reflecting: key), dumped,
            String(describing: [key]), String(describing: Optional(key)),
        ]
        for text in renderings {
            #expect(!text.contains("SECRET"), "\(text)")
            #expect(text.contains("…wxyz"), "\(text)")
        }
        #expect(key.description == "sk-…wxyz")
        #expect(Mirror(reflecting: key).children.map(\.label) == ["masked"])
    }

    @Test func aShortOrForeignKeyShowsLittle() {
        #expect(APIKey("sk-123").description == "…")
        #expect(APIKey("abcdefghijklmnop").description == "…mnop")
    }

    @Test func requestsCarryTheKeyOnlyInTheirAuthHeader() throws {
        let anthropic = try AnthropicRequest.urlRequest(for: sampleRequest(), key: testKey, baseURL: AnthropicProvider.defaultBaseURL)
        #expect(!String(decoding: try #require(anthropic.httpBody), as: UTF8.self).contains(testKey.rawValue))
        #expect(!(anthropic.url?.absoluteString.contains(testKey.rawValue) ?? true))
        let openAI = try OpenAIRequest.urlRequest(for: sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey, baseURL: OpenAIProvider.defaultBaseURL)
        #expect(!String(decoding: try #require(openAI.httpBody), as: UTF8.self).contains(testOpenAIKey.rawValue))
    }
}
