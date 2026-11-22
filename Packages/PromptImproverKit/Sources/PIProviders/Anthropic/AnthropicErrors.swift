import Foundation

/// Anthropic's errors as `EngineError`s: the HTTP table and the stream's `error` events.
enum AnthropicErrors {
    static let retryableStatuses: Set<Int> = [408, 409, 429, 500, 502, 503, 504, 529]

    /// - Parameters:
    ///   - model: The requested model (named by `.modelNotFound`); nil for the model list.
    ///   - knownSecrets: Secrets to scrub from the provider's message (the key in use).
    static func failure(for response: HTTPErrorResponse, model: String?, knownSecrets: [String], now: Date = Date()) -> AttemptFailure {
        let json = (try? JSONValue(parsing: response.body)) ?? JSONValue(raw: nil)
        let type = json["error"]["type"].string
        let message = json["error"]["message"].string ?? ""
        let errorCode = json["error"]["details"]["error_code"].string
        let status = response.head.status
        let retryAfter = response.head.retryAfter(now: now)
        let error: EngineError
        switch status {
        case 401:
            error = .invalidKey(.anthropic)
        case 402:
            error = .billing
        case 403:
            error = .permissionDenied
        case 404:
            error = model.map { .modelNotFound($0) } ?? .invalidRequest("Not found.")
        case 413:
            error = .contextTooLong
        case 429 where errorCode == "enforced_spend_limit_reached":
            // The tier's monthly spend cap: a 429 that keeps failing until the month turns.
            error = .billing
        case 429:
            error = .rateLimited(retryAfter: retryAfter)
        case 529:
            error = .overloaded
        case 400, 422:
            let lowered = message.lowercased()
            if lowered.contains("prompt is too long") {
                error = .contextTooLong
            } else if lowered.contains("reached your specified") && lowered.contains("usage limits") {
                // A spend limit the organization set itself comes back as a 400.
                error = .billing
            } else {
                error = .invalidRequest(Redactor.scrubbedMessage(message, knownSecrets: knownSecrets))
            }
        case 503:
            error = .overloaded
        case 500...599:
            error = type == "overloaded_error" ? .overloaded : .serverError(status: status)
        case 408, 409:
            error = .serverError(status: status)
        default:
            error = .invalidRequest(Redactor.scrubbedMessage(message, knownSecrets: knownSecrets))
        }
        return AttemptFailure(
            error: error,
            retryable: retryableStatuses.contains(status) && error != .billing,
            retryAfter: retryAfter,
            shouldRetry: response.head.shouldRetry,
            requestID: response.head.requestID ?? json["request_id"].string,
            httpStatus: status
        )
    }

    /// An `error` event inside a 200 stream. Only overloaded and server errors are retryable
    /// (and only while no text was emitted, which the retry policy checks).
    static func streamFailure(_ json: JSONValue, model: String, knownSecrets: [String], requestID: String?) -> AttemptFailure {
        let message = json["error"]["message"].string ?? ""
        let error: EngineError
        var retryable = false
        switch json["error"]["type"].string {
        case "overloaded_error":
            error = .overloaded
            retryable = true
        case "rate_limit_error":
            error = .rateLimited(retryAfter: nil)
        case "authentication_error":
            error = .invalidKey(.anthropic)
        case "permission_error":
            error = .permissionDenied
        case "billing_error":
            error = .billing
        case "not_found_error":
            error = .modelNotFound(model)
        case "request_too_large":
            error = .contextTooLong
        case "invalid_request_error":
            error = message.lowercased().contains("prompt is too long")
                ? .contextTooLong
                : .invalidRequest(Redactor.scrubbedMessage(message, knownSecrets: knownSecrets))
        case "timeout_error":
            error = .serverError(status: 504)
            retryable = true
        default:
            // api_error and any type added later.
            error = .serverError(status: 500)
            retryable = true
        }
        return AttemptFailure(error: error, retryable: retryable, requestID: requestID ?? json["request_id"].string)
    }
}
