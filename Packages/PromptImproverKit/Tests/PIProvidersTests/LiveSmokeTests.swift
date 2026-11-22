import Foundation
import Testing
@testable import PIProviders

/// Real requests against the real APIs, opt-in and never in CI. Spends a few cents' worth of
/// the cheapest model at low effort.
///
///     PI_LIVE_ANTHROPIC_KEY=sk-ant-… PI_LIVE_OPENAI_KEY=sk-… \
///     PI_RECORD_FIXTURES=/tmp/pi-fixtures \
///     swift test --package-path Packages/PromptImproverKit --filter LiveSmokeTests
///
/// `PI_RECORD_FIXTURES` also saves each raw event stream there, to refresh the hand-written
/// fixtures with what the APIs really send.
@Suite(.serialized, .timeLimit(.minutes(3)))
struct LiveSmokeTests {
    static let environment = ProcessInfo.processInfo.environment
    static let anthropicKey = environment["PI_LIVE_ANTHROPIC_KEY"].map(APIKey.init)
    static let openAIKey = environment["PI_LIVE_OPENAI_KEY"].map(APIKey.init)
    static let recordDirectory = environment["PI_RECORD_FIXTURES"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    private let session = ProviderSession.make()

    private static func request(_ preset: EnginePreset, _ provider: ProviderID) -> EngineRequest {
        EngineRequest(
            selection: ModelCatalog.selection(for: preset, provider: provider),
            maxOutputTokens: 2_000,
            systemBlocks: ["Rewrite the user's draft as a clear prompt. Reply with the prompt only."],
            turns: [.user("<draft>write a haiku about rain</draft>")]
        )
    }

    private func assertAnswers(_ provider: any PromptEngineProvider, key: APIKey) async {
        let outcome = await collect(provider.stream(Self.request(.fast, provider.id), key: key))
        #expect(outcome.failure == nil, "\(String(describing: outcome.failure))")
        #expect(outcome.events.contains { if case .textDelta = $0 { true } else { false } })
        #expect(outcome.finish == .complete)
    }

    private func assertListsCuratedModels(_ provider: any PromptEngineProvider, key: APIKey) async throws {
        let ids = Set(try await provider.models(key: key).map(\.id))
        for entry in ModelCatalog.curated(for: provider.id) {
            #expect(ids.contains(entry.model), "\(entry.model) missing from the list")
        }
    }

    private func assertRejectsBogusKey(_ provider: any PromptEngineProvider, prefix: String) async {
        await #expect(throws: EngineFailure.self) {
            do {
                _ = try await provider.models(key: APIKey(prefix + "bogus0000000000000000000000000000"))
            } catch let failure as EngineFailure {
                #expect(failure.error == .invalidKey(provider.id))
                throw failure
            }
        }
    }

    /// Saves the raw bytes of one streamed request, as sent by the request builders.
    private func record(_ name: String, _ urlRequest: URLRequest) async throws {
        guard let directory = Self.recordDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (bytes, _) = try await session.bytes(for: urlRequest)
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        try data.write(to: directory.appending(path: "\(name).sse"))
    }

    @Test(.enabled(if: anthropicKey != nil, "Set PI_LIVE_ANTHROPIC_KEY to run"))
    func anthropic() async throws {
        let key = try #require(Self.anthropicKey)
        let provider = AnthropicProvider(session: session)
        await assertAnswers(provider, key: key)
        try await assertListsCuratedModels(provider, key: key)
        await assertRejectsBogusKey(provider, prefix: "sk-ant-api03-")
        try await record("anthropic_live_ok_text", AnthropicRequest.urlRequest(for: Self.request(.fast, .anthropic), key: key, baseURL: AnthropicProvider.defaultBaseURL))
    }

    @Test(.enabled(if: openAIKey != nil, "Set PI_LIVE_OPENAI_KEY to run"))
    func openAI() async throws {
        let key = try #require(Self.openAIKey)
        let provider = OpenAIProvider(session: session)
        await assertAnswers(provider, key: key)
        try await assertListsCuratedModels(provider, key: key)
        await assertRejectsBogusKey(provider, prefix: "sk-proj-")
        try await record("openai_live_ok_text", OpenAIRequest.urlRequest(for: Self.request(.fast, .openai), key: key, baseURL: OpenAIProvider.defaultBaseURL))
    }
}
