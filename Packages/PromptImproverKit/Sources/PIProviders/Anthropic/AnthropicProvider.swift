import Foundation

/// Claude through the Messages API (`POST /v1/messages`), raw HTTP with the person's key.
public struct AnthropicProvider: PromptEngineProvider {
    /// The public API origin.
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    /// Sent as `anthropic-version` on every request.
    static let apiVersion = "2026-10-21"
    /// Sent as `anthropic-beta` on requests that ask for server-side fallback.
    static let serverSideFallbackBeta = "server-side-fallback-2026-07-01"
    static let requestIDHeader = "request-id"

    public var id: ProviderID { .anthropic }

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
        baseURL: URL = AnthropicProvider.defaultBaseURL,
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
            provider: .anthropic,
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
            urlRequest = .success(try AnthropicRequest.urlRequest(for: request, key: key, baseURL: baseURL))
        } catch {
            urlRequest = .failure(error)
        }
        let model = request.model
        let secrets = [key.rawValue]
        return driver.stream(
            urlRequest,
            handler: AnthropicStreamHandler(requestedModel: model, knownSecrets: secrets),
            mapHTTPError: { AnthropicErrors.failure(for: $0, model: model, knownSecrets: secrets) }
        )
    }

    /// `GET /v1/models`, every page.
    public func models(key: APIKey) async throws -> [RemoteModel] {
        guard !key.isEmpty else { throw EngineFailure(.missingKey(.anthropic), provider: .anthropic) }
        let secrets = [key.rawValue]
        var models: [RemoteModel] = []
        var afterID: String?
        // A generous bound on pages in case a proxy keeps saying `has_more`.
        for _ in 0..<20 {
            var components = URLComponents(url: baseURL.appending(path: "v1/models"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                + (afterID.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            guard let url = components?.url else { throw EngineFailure(.malformedResponse, provider: .anthropic) }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeouts.models.timeInterval
            AnthropicRequest.setCommonHeaders(on: &request, key: key)
            let (data, _) = try await HTTPExchange.data(
                for: request,
                session: session,
                provider: .anthropic,
                requestIDHeader: Self.requestIDHeader,
                mapHTTPError: { AnthropicErrors.failure(for: $0, model: nil, knownSecrets: secrets) }
            )
            guard let page = try? JSONValue(parsing: data), page["data"].raw is [Any] else {
                throw EngineFailure(.malformedResponse, provider: .anthropic)
            }
            models += page["data"].array.compactMap(Self.remoteModel)
            guard page["has_more"].bool == true, let last = page["last_id"].string, last != afterID else { break }
            afterID = last
        }
        return models
    }

    public func prewarm() async {
        await prewarmer.prewarm()
    }

    /// One entry of the model list, with the capabilities Anthropic reports for it. An effort
    /// block marked unsupported means the model takes no effort at all.
    static func remoteModel(_ json: JSONValue) -> RemoteModel? {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        let capabilities = json["capabilities"]
        let effort = capabilities["effort"]
        var efforts: [Effort]?
        if effort["supported"].bool == true {
            efforts = Effort.allCases.filter { $0 != .none && effort[$0.rawValue]["supported"].bool == true }
        } else if effort["supported"].bool == false {
            efforts = []
        }
        return RemoteModel(
            id: id,
            displayName: json["display_name"].string,
            maxOutputTokens: json["max_tokens"].int.flatMap { $0 > 0 ? $0 : nil },
            supportedEfforts: efforts,
            supportsThinkingDisabled: capabilities["thinking"]["types"]["disabled"]["supported"].bool
        )
    }
}
