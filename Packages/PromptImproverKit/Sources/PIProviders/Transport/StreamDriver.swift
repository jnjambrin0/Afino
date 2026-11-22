import Foundation
import PIFoundation
import os

/// Runs a streaming request to the end: attempts, back-off waits and the `AsyncThrowingStream`
/// around them. Everything happens inside the stream's one task, so dropping or cancelling the
/// stream cancels the request and any wait.
struct StreamDriver: Sendable {
    let provider: ProviderID
    let client: SSEClient
    let clock: EngineClock
    let policy: RetryPolicy
    /// A number in 0..<1 for the back-off jitter.
    let random: @Sendable () -> Double

    private static let logger = Log.logger(.engine)

    /// - Parameters:
    ///   - request: The request to send, or why it couldn't be built (a missing key, say).
    ///   - handler: The provider's event handler, copied fresh for each attempt.
    ///   - mapHTTPError: How the provider names an error response.
    func stream<Handler: SSEStreamHandler>(
        _ request: Result<URLRequest, EngineFailure>,
        handler: Handler,
        mapHTTPError: @escaping HTTPErrorMapper
    ) -> AsyncThrowingStream<EngineEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try request.get()
                    try await run(urlRequest, handler: handler, mapHTTPError: mapHTTPError, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: EngineFailure(normalizing: error, provider: provider))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run<Handler: SSEStreamHandler>(
        _ request: URLRequest,
        handler: Handler,
        mapHTTPError: @escaping HTTPErrorMapper,
        continuation: AsyncThrowingStream<EngineEvent, any Error>.Continuation
    ) async throws(EngineFailure) {
        var attempt = 1
        while true {
            guard !Task.isCancelled else { throw EngineFailure(.cancelled, provider: provider) }
            let sink = EventSink(continuation: continuation, activity: StreamActivity())
            do {
                try await client.run(request, handler: handler, mapHTTPError: mapHTTPError, sink: sink)
                return
            } catch {
                if Task.isCancelled { throw EngineFailure(.cancelled, provider: provider, requestID: error.requestID) }
                let decision = policy.decision(after: error, attempt: attempt, receivedText: sink.activity.receivedText, random: random())
                guard case let .retry(delay, reason) = decision else {
                    if error.error != .cancelled {
                        Self.logger.error("\(provider.rawValue, privacy: .public) attempt \(attempt) failed: \(error.error.logDescription, privacy: .public), status \(error.httpStatus ?? 0), request \(error.requestID ?? "-", privacy: .public)")
                    }
                    throw EngineFailure(error.error, provider: provider, requestID: error.requestID, httpStatus: error.httpStatus)
                }
                attempt += 1
                Self.logger.info("\(provider.rawValue, privacy: .public) retrying (attempt \(attempt)) in \(delay.timeInterval, format: .fixed(precision: 2)) s after \(String(describing: reason), privacy: .public), request \(error.requestID ?? "-", privacy: .public)")
                continuation.yield(.retrying(attempt: attempt, after: delay, reason: reason))
                do {
                    try await clock.sleep(delay)
                } catch {
                    throw EngineFailure(.cancelled, provider: provider)
                }
            }
        }
    }
}

/// One request that answers with plain JSON (the model list), mapped like a stream's errors.
enum HTTPExchange {
    static func data(
        for request: URLRequest,
        session: URLSession,
        provider: ProviderID,
        requestIDHeader: String,
        mapHTTPError: HTTPErrorMapper
    ) async throws(EngineFailure) -> (Data, ResponseHead) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled { throw EngineFailure(.cancelled, provider: provider) }
            guard let urlError = error as? URLError else { throw EngineFailure(normalizing: error, provider: provider) }
            throw EngineFailure(EngineError(urlError: urlError, headersReceived: false, receivedText: false), provider: provider)
        }
        guard let http = response as? HTTPURLResponse else { throw EngineFailure(.malformedResponse, provider: provider) }
        let head = ResponseHead(http, requestIDHeader: requestIDHeader)
        Log.logger(.network).info("\(request.httpMethod ?? "GET", privacy: .public) \(request.url?.path ?? "", privacy: .public) → \(head.status), \(data.count) bytes, request \(head.requestID ?? "-", privacy: .public)")
        guard head.isSuccess else {
            let failure = mapHTTPError(HTTPErrorResponse(head: head, body: data.prefix(HTTPErrorResponse.bodyLimit)))
            throw EngineFailure(failure.error, provider: provider, requestID: failure.requestID, httpStatus: head.status)
        }
        return (data, head)
    }
}
