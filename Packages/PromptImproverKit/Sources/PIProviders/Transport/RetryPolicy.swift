import Foundation

/// How one attempt failed, with what the retry decision needs.
struct AttemptFailure: Error, Sendable, Equatable {
    var error: EngineError
    /// Whether the retry table allows another attempt (before the first text delta).
    var retryable: Bool = false
    /// What the provider asked to wait (`retry-after-ms` / `Retry-After`).
    var retryAfter: Duration?
    /// `x-should-retry`, which overrides `retryable`.
    var shouldRetry: Bool?
    var requestID: String?
    var httpStatus: Int?
}

/// When to send a failed request again. Pure: the caller supplies the attempt number, whether
/// any text was emitted, and a random number for the jitter.
///
/// - Only while the failed attempt emitted no text: a retry must never duplicate or rewrite
///   text the person already saw.
/// - Only failures the table marks retryable (408, 409, non-billing 429, 500, 502, 503, 504,
///   529, a mid-stream overloaded or server error, a connection that timed out, dropped or
///   couldn't be made, the response-head watchdog), unless `x-should-retry` says otherwise.
/// - At most `maxAttempts` attempts in all.
/// - A requested wait (`Retry-After`) up to `maxRetryAfter` is honoured exactly; a longer one
///   fails at once rather than leave the panel waiting.
/// - Otherwise the waits are `backoff` with ±`jitter` (in `standard`: 0.5 s, then 1.5 s, ±25 %).
public struct RetryPolicy: Sendable, Equatable {
    /// Attempts in all, the first included.
    public var maxAttempts: Int
    /// The wait before each retry, in order; the last one repeats if there are more retries.
    public var backoff: [Duration]
    /// How far a wait may stray from `backoff`, as a fraction of it.
    public var jitter: Double
    /// The longest `Retry-After` worth waiting for.
    public var maxRetryAfter: Duration

    public init(maxAttempts: Int, backoff: [Duration], jitter: Double, maxRetryAfter: Duration) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
        self.jitter = jitter
        self.maxRetryAfter = maxRetryAfter
    }

    /// What the app uses: three attempts, waits of 0.5 s and 1.5 s, and `Retry-After` up to 20 s.
    public static let standard = RetryPolicy(
        maxAttempts: 3,
        backoff: [.milliseconds(500), .milliseconds(1_500)],
        jitter: 0.25,
        maxRetryAfter: .seconds(20)
    )

    /// Never retries.
    public static let none = RetryPolicy(maxAttempts: 1, backoff: [], jitter: 0, maxRetryAfter: .zero)

    enum Decision: Sendable, Equatable {
        case retry(after: Duration, reason: RetryReason)
        case giveUp
    }

    /// Whether to send the request again, and after how long.
    ///
    /// - Parameters:
    ///   - failure: How the attempt failed.
    ///   - attempt: The number of the attempt that failed, from 1.
    ///   - receivedText: Whether that attempt emitted any text.
    ///   - random: A number in 0..<1 for the jitter.
    func decision(after failure: AttemptFailure, attempt: Int, receivedText: Bool, random: Double) -> Decision {
        guard !receivedText, failure.error != .cancelled else { return .giveUp }
        guard failure.shouldRetry ?? failure.retryable else { return .giveUp }
        guard attempt < maxAttempts else { return .giveUp }
        let reason = Self.reason(for: failure)
        if let requested = failure.retryAfter {
            return requested <= maxRetryAfter ? .retry(after: requested, reason: reason) : .giveUp
        }
        guard let base = backoff.isEmpty ? nil : backoff[min(attempt - 1, backoff.count - 1)] else {
            return .retry(after: .zero, reason: reason)
        }
        let unit = min(max(random, 0), 1)
        let factor = 1 + jitter * (2 * unit - 1)
        return .retry(after: base * factor, reason: reason)
    }

    /// What the retry tells the person. A failure that is retried only because the provider
    /// asked for it falls through to `.requestedByServer`.
    static func reason(for failure: AttemptFailure) -> RetryReason {
        switch failure.error {
        case .rateLimited: .rateLimited
        case .overloaded: .overloaded
        case let .serverError(status): .serverError(status: status)
        case .timedOut: .timedOut
        case .offline, .connectionLost: .network
        default: .requestedByServer
        }
    }
}
