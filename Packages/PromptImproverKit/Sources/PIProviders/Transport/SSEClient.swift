import Foundation
import PIFoundation
import Synchronization
import os

/// Reads one provider's event stream: decides what each event means and when the stream ends.
/// A fresh copy runs each attempt.
protocol SSEStreamHandler: Sendable {
    /// The response head of a 2xx event stream arrived.
    mutating func begin(_ head: ResponseHead)
    /// Handles one event; true when it ends the answer. A provider error event throws.
    mutating func handle(_ event: SSEEvent, emit: (EngineEvent) -> Void) throws(AttemptFailure) -> Bool
}

/// What one attempt has done so far, shared by the reader and its watchdog.
final class StreamActivity: Sendable {
    private let bytesRead = Atomic<Int>(0)
    private let headReceived = Atomic<Bool>(false)
    private let textEmitted = Atomic<Bool>(false)
    private let head = Mutex<ResponseHead?>(nil)

    var byteCount: Int { bytesRead.load(ordering: .relaxed) }
    var headersReceived: Bool { headReceived.load(ordering: .acquiring) }
    var receivedText: Bool { textEmitted.load(ordering: .acquiring) }
    var responseHead: ResponseHead? { head.withLock { $0 } }

    func touch() { bytesRead.wrappingAdd(1, ordering: .relaxed) }

    func received(_ head: ResponseHead) {
        self.head.withLock { $0 = head }
        headReceived.store(true, ordering: .releasing)
    }

    func emittedText() { textEmitted.store(true, ordering: .releasing) }
}

/// Where an attempt's events go: the consumer's stream, noting any text on the way.
struct EventSink: Sendable {
    let continuation: AsyncThrowingStream<EngineEvent, any Error>.Continuation
    let activity: StreamActivity

    func emit(_ event: EngineEvent) {
        if case .textDelta = event { activity.emittedText() }
        continuation.yield(event)
    }
}

/// One HTTP exchange that answers with server-sent events, shared by every provider.
///
/// Opens the request with `URLSession.bytes(for:)` (not `.lines`, which drops the blank lines
/// that end SSE events), reads a non-2xx body (up to 64 KB) for the provider to map, rejects a
/// 2xx that isn't `text/event-stream`, and hands each event to the provider's handler. Two
/// watchdogs run beside the reader on the continuous clock: no response head within
/// `responseHeaders` (retryable), and no byte at all for `idle` once the response started.
struct SSEClient: Sendable {
    let session: URLSession
    let timeouts: StreamTimeouts
    let requestIDHeader: String

    private static let logger = Log.logger(.network)

    struct WatchdogFired: Error, Equatable {
        let phase: TimeoutPhase
    }

    /// Sends `request` and feeds the handler until the stream ends or fails. Events reach the
    /// consumer through `sink` as they arrive.
    func run<Handler: SSEStreamHandler>(
        _ request: URLRequest,
        handler: Handler,
        mapHTTPError: @escaping HTTPErrorMapper,
        sink: EventSink
    ) async throws(AttemptFailure) {
        let activity = sink.activity
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await read(request, handler: handler, mapHTTPError: mapHTTPError, sink: sink)
                }
                group.addTask {
                    try await Self.watch(activity, timeouts: timeouts)
                }
                // Whichever ends first decides; the other is cancelled.
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            throw Self.failure(for: error, activity: activity)
        }
    }

    private func read<Handler: SSEStreamHandler>(
        _ request: URLRequest,
        handler: Handler,
        mapHTTPError: HTTPErrorMapper,
        sink: EventSink
    ) async throws {
        let activity = sink.activity
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AttemptFailure(error: .malformedResponse)
        }
        let head = ResponseHead(http, requestIDHeader: requestIDHeader)
        activity.received(head)
        Self.logger.info("\(request.httpMethod ?? "GET", privacy: .public) \(request.url?.path ?? "", privacy: .public) → \(head.status) request \(head.requestID ?? "-", privacy: .public)")

        guard head.isSuccess else {
            var body = Data()
            for try await byte in bytes {
                activity.touch()
                body.append(byte)
                if body.count >= HTTPErrorResponse.bodyLimit { break }
            }
            throw mapHTTPError(HTTPErrorResponse(head: head, body: body))
        }
        guard head.isEventStream else {
            Self.logger.error("Expected an event stream, got \(head.value("content-type") ?? "no content type", privacy: .public)")
            throw AttemptFailure(error: .malformedResponse, requestID: head.requestID, httpStatus: head.status)
        }

        var handler = handler
        handler.begin(head)
        var parser = SSEParser()
        for try await byte in bytes {
            activity.touch()
            guard let event = try parser.append(byte) else { continue }
            if try handler.handle(event, emit: sink.emit) {
                Self.logger.info("Stream ended after \(activity.byteCount) bytes, request \(head.requestID ?? "-", privacy: .public)")
                return
            }
        }
        if let event = parser.finish(), try handler.handle(event, emit: sink.emit) { return }
        // The connection closed before the provider's terminal event: cut off on the way.
        Self.logger.error("Stream closed without a terminal event after \(activity.byteCount) bytes, request \(head.requestID ?? "-", privacy: .public)")
        throw AttemptFailure(
            error: .connectionLost(receivedText: activity.receivedText),
            retryable: true,
            requestID: head.requestID,
            httpStatus: head.status
        )
    }

    /// Throws `WatchdogFired` when a wait runs out; cancelled when the reader ends first.
    /// Wakes once a second (more often only for timeouts under ten seconds, as in tests), so it
    /// costs next to nothing while a model thinks for minutes.
    static func watch(_ activity: StreamActivity, timeouts: StreamTimeouts) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var lastCount = activity.byteCount
        var lastProgress = start
        var sawHead = false
        let interval = min(.seconds(1), min(timeouts.responseHeaders, timeouts.idle) / 10)
        while true {
            try await clock.sleep(for: interval)
            let now = clock.now
            if !sawHead {
                if activity.headersReceived {
                    sawHead = true
                    lastProgress = now
                    lastCount = activity.byteCount
                } else if start.duration(to: now) >= timeouts.responseHeaders {
                    throw WatchdogFired(phase: .responseHeaders)
                }
                continue
            }
            let count = activity.byteCount
            if count != lastCount {
                lastCount = count
                lastProgress = now
            } else if lastProgress.duration(to: now) >= timeouts.idle {
                throw WatchdogFired(phase: .idle)
            }
        }
    }

    /// Whatever ended the attempt, as an `AttemptFailure` the retry policy can judge. Only the
    /// response-head watchdog and transient transport errors are retryable here; provider
    /// errors arrive already mapped.
    static func failure(for error: any Error, activity: StreamActivity) -> AttemptFailure {
        let head = activity.responseHead
        switch error {
        case let failure as AttemptFailure:
            return failure
        case let fired as WatchdogFired:
            logger.error("No \(fired.phase == .responseHeaders ? "response" : "data", privacy: .public) in time, request \(head?.requestID ?? "-", privacy: .public)")
            return AttemptFailure(
                error: .timedOut(fired.phase),
                retryable: fired.phase == .responseHeaders,
                requestID: head?.requestID,
                httpStatus: head?.status
            )
        case is SSEParser.ParseError:
            return AttemptFailure(error: .malformedResponse, requestID: head?.requestID, httpStatus: head?.status)
        case is CancellationError:
            return AttemptFailure(error: .cancelled, requestID: head?.requestID)
        case let urlError as URLError:
            let mapped = EngineError(urlError: urlError, headersReceived: activity.headersReceived, receivedText: activity.receivedText)
            if mapped != .cancelled {
                logger.error("Transport error \(urlError.code.rawValue), request \(head?.requestID ?? "-", privacy: .public)")
            }
            let transient: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost]
            return AttemptFailure(
                error: mapped,
                retryable: transient.contains(urlError.code),
                requestID: head?.requestID,
                httpStatus: head?.status
            )
        default:
            return AttemptFailure(
                error: .connectionLost(receivedText: activity.receivedText),
                requestID: head?.requestID,
                httpStatus: head?.status
            )
        }
    }
}
