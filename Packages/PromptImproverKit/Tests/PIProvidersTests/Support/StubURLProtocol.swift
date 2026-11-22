import Foundation
import Synchronization

/// One step of a scripted HTTP response.
enum StubStep: Sendable {
    case head(status: Int, headers: [String: String])
    case chunk(Data)
    case delay(Duration)
    case finish
    case fail(URLError.Code)
}

/// A request as the stub received it. `URLProtocol` sees no `httpBody`, so the body is read
/// from `httpBodyStream`.
struct RecordedRequest: Sendable {
    var method: String
    var url: URL
    /// Header fields by lowercased name.
    var headers: [String: String]
    var body: Data?

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url ?? URL(fileURLWithPath: "/")
        var headers: [String: String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] { headers[name.lowercased()] = value }
        self.headers = headers
        body = request.httpBody ?? Self.read(request.httpBodyStream)
    }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// The body parsed as a JSON object.
    var json: [String: Any] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A fake API host for one test. Each request takes the next scripted response in order; the
/// host name is unique, so tests run in parallel without seeing each other's traffic.
final class StubServer: Sendable {
    let host: String
    let baseURL: URL
    private let state = Mutex<(queue: [[StubStep]], requests: [RecordedRequest])>(([], []))

    init() {
        host = "stub-\(UUID().uuidString.lowercased().prefix(13)).test"
        baseURL = URL(string: "https://\(host)")!
        stubRegistry.register(self)
    }

    var requests: [RecordedRequest] { state.withLock { $0.requests } }

    func enqueue(_ steps: [StubStep]) {
        state.withLock { $0.queue.append(steps) }
    }

    /// A 200 event stream, sent in pieces of `chunkSize` bytes (whole when nil).
    func enqueueStream(_ data: Data, chunkSize: Int? = nil, headers: [String: String] = [:]) {
        var head = ["Content-Type": "text/event-stream; charset=utf-8"]
        head.merge(headers) { _, new in new }
        enqueue([.head(status: 200, headers: head)] + Fixture.chunks(data, size: chunkSize).map(StubStep.chunk) + [.finish])
    }

    /// A JSON response (an error body or a model list).
    func enqueueJSON(status: Int, body: Data, headers: [String: String] = [:]) {
        var head = ["Content-Type": "application/json"]
        head.merge(headers) { _, new in new }
        enqueue([.head(status: status, headers: head), .chunk(body), .finish])
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func next(for request: RecordedRequest) -> [StubStep] {
        state.withLock { state in
            state.requests.append(request)
            return state.queue.isEmpty ? [.fail(.resourceUnavailable)] : state.queue.removeFirst()
        }
    }
}

final class StubRegistry: Sendable {
    private let servers = Mutex<[String: StubServer]>([:])

    func register(_ server: StubServer) {
        servers.withLock { $0[server.host] = server }
    }

    func server(for host: String) -> StubServer? {
        servers.withLock { $0[host] }
    }
}

/// `URLProtocol` instances are made by the URL loading system, so the stub finds its server
/// through this registry rather than through an initializer.
let stubRegistry = StubRegistry()

/// Plays a `StubServer`'s script for each request: the head, the body in chunks with optional
/// pauses, then the end or a transport error. `stopLoading` (a cancelled request) stops it.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private let playback = Mutex<Task<Void, Never>?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(request)
        guard let host = request.url?.host(), let server = stubRegistry.server(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let steps = server.next(for: recorded)
        let task = Task { await self.play(steps) }
        playback.withLock { $0 = task }
    }

    override func stopLoading() {
        playback.withLock { $0?.cancel() }
    }

    private func play(_ steps: [StubStep]) async {
        guard let url = request.url else { return }
        for step in steps {
            guard !Task.isCancelled else { return }
            switch step {
            case let .head(status, headers):
                guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            case let .chunk(data):
                client?.urlProtocol(self, didLoad: data)
            case let .delay(duration):
                do { try await Task.sleep(for: duration) } catch { return }
            case .finish:
                client?.urlProtocolDidFinishLoading(self)
                return
            case let .fail(code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
                return
            }
        }
    }
}
