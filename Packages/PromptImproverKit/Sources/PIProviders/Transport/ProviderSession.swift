import Foundation

/// The `URLSession` every provider shares: ephemeral, no cache, no cookies, no stored
/// credentials, and no waiting for connectivity (offline fails at once). Auth headers are set
/// on each request, never in `httpAdditionalHeaders`, so the session itself holds no secret.
public enum ProviderSession {
    /// Seconds without data before URLSession gives up; the stream's own idle watchdog is the
    /// same 300 s, the response-head watchdog is 20 s.
    static let requestTimeout: TimeInterval = 300
    /// Seconds a whole request may take.
    static let resourceTimeout: TimeInterval = 600

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpAdditionalHeaders = nil
        return configuration
    }

    /// A new session with this configuration. The app makes one and shares it between both
    /// providers.
    public static func make() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }
}

/// How long a stream may wait. `standard` holds the values the app uses; tests shorten them.
public struct StreamTimeouts: Sendable, Equatable {
    /// From sending the request to its response head. Retried when it runs out.
    public var responseHeaders: Duration
    /// Without a single byte once the response started. Long silences shorter than this are
    /// normal (a model thinking) and are not errors.
    public var idle: Duration
    /// For `models(key:)`, which validates a key while the person waits.
    public var models: Duration
    /// For the prewarm `HEAD`.
    public var prewarm: Duration

    public init(responseHeaders: Duration, idle: Duration, models: Duration, prewarm: Duration) {
        self.responseHeaders = responseHeaders
        self.idle = idle
        self.models = models
        self.prewarm = prewarm
    }

    /// 20 s for the response head, 300 s of silence, 30 s for the model list, 3 s for a prewarm.
    public static let standard = StreamTimeouts(
        responseHeaders: .seconds(20),
        idle: .seconds(300),
        models: .seconds(30),
        prewarm: .seconds(3)
    )

    /// The wait that `phase` names, for messages such as "No response after 20 s".
    public func limit(for phase: TimeoutPhase) -> Duration {
        switch phase {
        case .responseHeaders: responseHeaders
        case .idle: idle
        }
    }
}

extension Duration {
    /// The duration in seconds, for Foundation APIs.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
    }
}

/// Any `Clock<Duration>` behind one concrete type, so providers needn't be generic over it. It
/// times back-off waits and the prewarm rate limit; tests pass a clock they control.
struct EngineClock: Sendable {
    /// Time since the clock was wrapped.
    let now: @Sendable () -> Duration
    /// Waits for a duration; throws when the task is cancelled.
    let sleep: @Sendable (Duration) async throws -> Void

    init<C: Clock>(_ clock: C) where C.Duration == Duration {
        let origin = clock.now
        now = { origin.duration(to: clock.now) }
        sleep = { duration in try await clock.sleep(for: duration) }
    }
}
