import Foundation
import PIFoundation
import Synchronization
import os

/// Opens the connection to a provider before the first request needs it (DNS, TLS, HTTP/2),
/// on the same session the request will use: a `HEAD` to the provider's origin without
/// credentials, at most once per `interval`. Whatever it answers is ignored.
final class Prewarmer: Sendable {
    /// The shortest time between two prewarms of the same provider.
    static let interval: Duration = .seconds(60)

    private let session: URLSession
    private let origin: URL?
    private let clock: EngineClock
    private let timeout: Duration
    private let lastStart = Mutex<Duration?>(nil)

    init(session: URLSession, baseURL: URL, clock: EngineClock, timeout: Duration) {
        self.session = session
        origin = Self.origin(of: baseURL)
        self.clock = clock
        self.timeout = timeout
    }

    func prewarm() async {
        guard let origin, claim() else { return }
        var request = URLRequest(url: origin)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout.timeInterval
        let status = (try? await session.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
        Log.logger(.network).debug("Prewarmed \(origin.host() ?? "-", privacy: .public): \(status.map(String.init) ?? "failed", privacy: .public)")
    }

    /// True when no prewarm started within the last `interval`; marks this one as started.
    func claim() -> Bool {
        let now = clock.now()
        return lastStart.withLock { last in
            if let last, now - last < Self.interval { return false }
            last = now
            return true
        }
    }

    /// `scheme://host[:port]/` of `url`.
    static func origin(of url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var origin = URLComponents()
        origin.scheme = components.scheme
        origin.host = components.host
        origin.port = components.port
        origin.path = "/"
        return origin.url
    }
}
