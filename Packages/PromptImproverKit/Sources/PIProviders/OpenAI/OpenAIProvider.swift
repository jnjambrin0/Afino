import Foundation

/// GPT through the Responses API (`POST /v1/responses`), raw HTTP with the person's key.
public struct OpenAIProvider: PromptEngineProvider {
    /// The public API origin.
    public static let defaultBaseURL = URL(string: "https://api.openai.com")!
    static let requestIDHeader = "x-request-id"

    public var id: ProviderID { .openai }

    private let session: URLSession
    private let baseURL: URL
    private let timeouts: StreamTimeouts
    private let driver: StreamDriver
    private let prewarmer: Prewarmer

    /// - Parameters:
    ///   - session: Usually `ProviderSession.make()`, shared by both providers.
    ///   - baseURL: The API origin; tests point it at a stub host.
    ///   - clock: Times back-off waits and the prewarm rate limit. The stream watchdogs always
    ///     run on the continuous clock with `timeouts`.
    ///   - retryPolicy: When to send a failed request again.
    ///   - timeouts: The stream and request waits.
    ///   - random: A number in 0..<1 for the back-off jitter.
    public init(
        session: URLSession,
        baseURL: URL = OpenAIProvider.defaultBaseURL,
        clock: some Clock<Duration> = ContinuousClock(),
        retryPolicy: RetryPolicy = .standard,
        timeouts: StreamTimeouts = .standard,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.timeouts = timeouts
        let engineClock = EngineClock(clock)
        driver = StreamDriver(
            provider: .openai,
            client: SSEClient(session: session, timeouts: timeouts, requestIDHeader: Self.requestIDHeader),
            clock: engineClock,
            policy: retryPolicy,
            random: random
        )
        prewarmer = Prewarmer(session: session, baseURL: baseURL, clock: engineClock, timeout: timeouts.prewarm)
    }

    public func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        let urlRequest: Result<URLRequest, EngineFailure>
        do {
            urlRequest = .success(try OpenAIRequest.urlRequest(for: request, key: key, baseURL: baseURL))
        } catch {
            urlRequest = .failure(error)
        }
        let model = request.model
        let secrets = [key.rawValue]
        return driver.stream(
            urlRequest,
            handler: OpenAIStreamHandler(requestedModel: model, knownSecrets: secrets),
            mapHTTPError: { OpenAIErrors.failure(for: $0, model: model, knownSecrets: secrets) }
        )
    }

    /// `GET /v1/models`, keeping the GPT text models: ids that start `gpt-` and a digit, minus
    /// the audio, realtime, image, embedding, speech and transcription variants.
    public func models(key: APIKey) async throws -> [RemoteModel] {
        guard !key.isEmpty else { throw EngineFailure(.missingKey(.openai), provider: .openai) }
        let secrets = [key.rawValue]
        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeouts.models.timeInterval
        OpenAIRequest.setAuthorization(on: &request, key: key)
        let (data, _) = try await HTTPExchange.data(
            for: request,
            session: session,
            provider: .openai,
            requestIDHeader: Self.requestIDHeader,
            mapHTTPError: { OpenAIErrors.failure(for: $0, model: nil, knownSecrets: secrets) }
        )
        guard let list = try? JSONValue(parsing: data), list["data"].raw is [Any] else {
            throw EngineFailure(.malformedResponse, provider: .openai)
        }
        return list["data"].array
            .compactMap { $0["id"].string }
            .filter(Self.isTextModel)
            .map { RemoteModel(id: $0) }
    }

    public func prewarm() async {
        await prewarmer.prewarm()
    }

    /// Substrings that mark a GPT id as something other than a text model.
    static let excludedVariants = ["audio", "realtime", "image", "embedding", "tts", "transcribe"]

    /// Whether `id` names a GPT text model: `gpt-` and a digit, and none of `excludedVariants`.
    static func isTextModel(_ id: String) -> Bool {
        let lowered = id.lowercased()
        guard lowered.wholeMatch(of: #/gpt-\d.*/#) != nil else { return false }
        return !excludedVariants.contains { lowered.contains($0) }
    }
}
