import Foundation

/// What went wrong, in terms the panel can turn into one line ("what happened + what to do").
/// Provider messages only ever reach `invalidRequest`, and only after `Redactor.scrub`.
public enum EngineError: Error, Sendable, Equatable, Hashable {
    /// No key is stored for the provider, so nothing was sent.
    case missingKey(ProviderID)
    /// The provider rejected the key.
    case invalidKey(ProviderID)
    /// The key is valid but not allowed to do this.
    case permissionDenied
    /// Out of credit, or a spend limit was reached.
    case billing
    /// The key can't use this model (or it doesn't exist).
    case modelNotFound(String)
    /// The draft and conversation exceed what the model accepts.
    case contextTooLong
    /// The provider rejected the request; the message is redacted and shortened.
    case invalidRequest(String)
    /// Too many requests; `retryAfter` is the wait the provider asked for, if it named one.
    case rateLimited(retryAfter: Duration?)
    /// The provider is temporarily over capacity.
    case overloaded
    /// A failure on the provider's side, by HTTP status. A stream error event, which has no
    /// status of its own, reports 500 (or 504 for a provider timeout).
    case serverError(status: Int)
    /// The Mac is offline or the host could not be reached.
    case offline
    case timedOut(TimeoutPhase)
    /// The connection dropped; `receivedText` says whether any of the answer had arrived.
    case connectionLost(receivedText: Bool)
    /// The secure connection failed: a certificate problem, or a network that intercepts TLS.
    case secureConnection
    /// The provider answered with something that is not the expected API response.
    case malformedResponse
    /// The request was cancelled; never shown as an error.
    case cancelled
}

/// Which wait ran out.
public enum TimeoutPhase: String, Sendable, Equatable, Hashable, CaseIterable {
    /// No response head within `StreamTimeouts.responseHeaders` (20 s by default).
    case responseHeaders
    /// No bytes for `StreamTimeouts.idle` (300 s by default) once the answer had started.
    case idle
}

/// An `EngineError` with what identifies the failed request: the provider, its request id (for
/// "Copy details" and support tickets) and the HTTP status. Providers always throw this type.
public struct EngineFailure: Error, Sendable, Equatable, CustomStringConvertible {
    /// What went wrong.
    public var error: EngineError
    /// The provider the request went to, when known.
    public var provider: ProviderID?
    /// The provider's identifier for the request (`request-id`, `x-request-id`).
    public var requestID: String?
    /// The response's HTTP status, when one arrived.
    public var httpStatus: Int?

    public init(_ error: EngineError, provider: ProviderID? = nil, requestID: String? = nil, httpStatus: Int? = nil) {
        self.error = error
        self.provider = provider
        self.requestID = requestID
        self.httpStatus = httpStatus
    }

    /// Any error as an `EngineFailure`: an `EngineFailure` stays as it is, an `EngineError` is
    /// wrapped, cancellation becomes `.cancelled`, a `URLError` is mapped, anything else is
    /// `.malformedResponse`.
    public init(normalizing error: any Error, provider: ProviderID? = nil) {
        switch error {
        case let failure as EngineFailure:
            self = failure
            if self.provider == nil { self.provider = provider }
        case let engineError as EngineError:
            self.init(engineError, provider: provider)
        case is CancellationError:
            self.init(.cancelled, provider: provider)
        case let urlError as URLError:
            self.init(EngineError(urlError: urlError, headersReceived: false, receivedText: false), provider: provider)
        default:
            self.init(.malformedResponse, provider: provider)
        }
    }

    /// The case and the identifying details, for logs and "Copy details". Holds no secret: an
    /// `invalidRequest` message has been scrubbed already.
    public var description: String {
        var details: [String] = []
        if let provider { details.append("provider: \(provider.rawValue)") }
        if let httpStatus { details.append("status: \(httpStatus)") }
        if let requestID { details.append("request: \(requestID)") }
        return details.isEmpty ? "\(error)" : "\(error) [\(details.joined(separator: ", "))]"
    }
}

extension EngineError {
    /// The case without any provider text, for logs: they hold status codes and request ids,
    /// never a message that might quote the prompt.
    var logDescription: String {
        switch self {
        case let .missingKey(provider): "missingKey(\(provider.rawValue))"
        case let .invalidKey(provider): "invalidKey(\(provider.rawValue))"
        case .permissionDenied: "permissionDenied"
        case .billing: "billing"
        case let .modelNotFound(model): "modelNotFound(\(model))"
        case .contextTooLong: "contextTooLong"
        case .invalidRequest: "invalidRequest"
        case let .rateLimited(retryAfter): "rateLimited(\(retryAfter.map { "\($0.timeInterval) s" } ?? "-"))"
        case .overloaded: "overloaded"
        case let .serverError(status): "serverError(\(status))"
        case .offline: "offline"
        case let .timedOut(phase): "timedOut(\(phase.rawValue))"
        case let .connectionLost(receivedText): "connectionLost(receivedText: \(receivedText))"
        case .secureConnection: "secureConnection"
        case .malformedResponse: "malformedResponse"
        case .cancelled: "cancelled"
        }
    }

    /// A transport error as the panel should name it.
    /// - Parameters:
    ///   - headersReceived: Whether the response head had arrived (a time-out is then `.idle`).
    ///   - receivedText: Whether any answer text had been emitted (for `.connectionLost`).
    init(urlError: URLError, headersReceived: Bool, receivedText: Bool) {
        switch urlError.code {
        case .cancelled, .userCancelledAuthentication:
            self = .cancelled
        case .notConnectedToInternet, .dataNotAllowed, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff, .callIsActive, .cannotConnectToHost:
            self = .offline
        case .timedOut:
            self = .timedOut(headersReceived ? .idle : .responseHeaders)
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            self = .secureConnection
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData:
            self = .malformedResponse
        default:
            // networkConnectionLost and everything else that drops a connection.
            self = .connectionLost(receivedText: receivedText)
        }
    }
}
