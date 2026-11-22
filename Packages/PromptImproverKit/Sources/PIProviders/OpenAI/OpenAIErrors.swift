import Foundation

/// OpenAI's errors as `EngineError`s: the HTTP table, `response.failed` and `error` events.
enum OpenAIErrors {
    static let retryableStatuses: Set<Int> = [408, 409, 429, 500, 502, 503, 504]

    /// Codes (or types) of a 429 that won't clear by waiting: no credit or a spend limit.
    static let billingCodes: Set<String> = [
        "insufficient_quota",
        "credit_balance_exhausted",
        "organization_spend_limit_exceeded",
        "project_spend_limit_exceeded",
        "organization_usage_limit_exceeded",
    ]

    /// - Parameters:
    ///   - model: The requested model (named by `.modelNotFound`); nil for the model list.
    ///   - knownSecrets: Secrets to scrub from the provider's message (the key in use).
    static func failure(for response: HTTPErrorResponse, model: String?, knownSecrets: [String], now: Date = Date()) -> AttemptFailure {
        let json = (try? JSONValue(parsing: response.body)) ?? JSONValue(raw: nil)
        let code = json["error"]["code"].text
        let type = json["error"]["type"].string
        let message = json["error"]["message"].string ?? ""
        let status = response.head.status
        let retryAfter = response.head.retryAfter(now: now)
        let error: EngineError
        if status == 401 {
            // Never OpenAI's message here: it echoes (part of) the key.
            error = .invalidKey(.openai)
        } else if status == 403 {
            error = .permissionDenied
        } else if status == 404 || code == "model_not_found" {
            error = model.map { .modelNotFound($0) } ?? .invalidRequest("Not found.")
        } else if code == "context_length_exceeded" || status == 413 {
            error = .contextTooLong
        } else if status == 402 || (status == 429 && (code.map(billingCodes.contains) == true || type.map(billingCodes.contains) == true)) {
            error = .billing
        } else if status == 429 {
            error = .rateLimited(retryAfter: retryAfter)
        } else if status == 503 {
            error = .overloaded
        } else if status >= 500 || status == 408 || status == 409 {
            error = .serverError(status: status)
        } else {
            error = .invalidRequest(Redactor.scrubbedMessage(message, knownSecrets: knownSecrets))
        }
        return AttemptFailure(
            error: error,
            retryable: retryableStatuses.contains(status) && error != .billing,
            retryAfter: retryAfter,
            shouldRetry: response.head.shouldRetry,
            requestID: response.head.requestID,
            httpStatus: status
        )
    }

    /// The `error` of a `response.failed` event, or an `error` event. Only server and overload
    /// failures are retryable (while no text was emitted, which the retry policy checks).
    static func streamFailure(code: String?, message: String?, model: String, knownSecrets: [String], requestID: String?) -> AttemptFailure {
        let error: EngineError
        var retryable = false
        switch code {
        case let code? where billingCodes.contains(code):
            error = .billing
        case "invalid_api_key":
            error = .invalidKey(.openai)
        case "model_not_found":
            error = .modelNotFound(model)
        case "context_length_exceeded":
            error = .contextTooLong
        case "rate_limit_exceeded":
            error = .rateLimited(retryAfter: nil)
        case let code? where code.contains("overloaded"):
            error = .overloaded
            retryable = true
        case let code? where code.hasPrefix("invalid"):
            error = .invalidRequest(Redactor.scrubbedMessage(message ?? "", knownSecrets: knownSecrets))
        default:
            // server_error, a missing code, and anything added later.
            error = .serverError(status: 500)
            retryable = true
        }
        return AttemptFailure(error: error, retryable: retryable, requestID: requestID)
    }
}
