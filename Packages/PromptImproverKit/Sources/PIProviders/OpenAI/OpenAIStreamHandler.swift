import Foundation

/// The Responses API stream as `EngineEvent`s, dispatched on each event's JSON `type`.
///
/// - `response.created` → `.started` (the model from `response.model`, the id from `x-request-id`)
/// - `response.output_item.added` of a `reasoning` item → `.thinking`
/// - `response.output_text.delta` → `.textDelta` (the text is in `delta`)
/// - a `refusal` content part, `response.refusal.delta` or `response.refusal.done` → remembers
///   that the answer is a refusal
/// - `response.completed` → `.finished(.complete)`, or `.refused` when the answer was a refusal
/// - `response.incomplete` → `.truncated` for `max_output_tokens`, `.refused` for `content_filter`
/// - `response.failed` and `error` → throw; everything else is ignored
struct OpenAIStreamHandler: SSEStreamHandler {
    let requestedModel: String
    let knownSecrets: [String]
    private var requestID: String?
    private var started = false
    private var sawRefusal = false

    init(requestedModel: String, knownSecrets: [String]) {
        self.requestedModel = requestedModel
        self.knownSecrets = knownSecrets
    }

    mutating func begin(_ head: ResponseHead) {
        requestID = head.requestID
    }

    mutating func handle(_ event: SSEEvent, emit: (EngineEvent) -> Void) throws(AttemptFailure) -> Bool {
        let data = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !data.isEmpty, data != "[DONE]" else { return false }
        guard let json = try? JSONValue(parsing: data) else {
            throw AttemptFailure(error: .malformedResponse, requestID: requestID)
        }
        switch json["type"].string {
        case "response.created":
            started = true
            emit(.started(servedModel: json["response"]["model"].string ?? requestedModel, requestID: requestID))
        case "response.output_item.added":
            if json["item"]["type"].string == "reasoning" {
                startIfNeeded(emit)
                emit(.thinking)
            }
        case "response.output_text.delta":
            guard let text = json["delta"].string, !text.isEmpty else { break }
            startIfNeeded(emit)
            emit(.textDelta(text))
        case "response.content_part.added":
            // A refusal is a content part of type "refusal", streamed with its own
            // `response.refusal.delta` and `response.refusal.done` events; any of them marks the
            // answer as refused, and its text is never treated as the answer.
            if json["part"]["type"].string == "refusal" { sawRefusal = true }
        case "response.refusal.delta", "response.refusal.done":
            sawRefusal = true
        case "response.completed":
            startIfNeeded(emit)
            let response = json["response"]
            let refused = sawRefusal || Self.containsRefusal(response["output"])
            emit(.finished(refused ? .refused(category: nil) : .complete, usage: TokenUsage(openAI: response["usage"]).nonEmpty))
            return true
        case "response.incomplete":
            startIfNeeded(emit)
            let response = json["response"]
            let reason: FinishReason = switch response["incomplete_details"]["reason"].string {
            case "content_filter": .refused(category: "content_filter")
            default: .truncated // max_output_tokens, and any other reason the answer stopped short
            }
            emit(.finished(reason, usage: TokenUsage(openAI: response["usage"]).nonEmpty))
            return true
        case "response.failed":
            let error = json["response"]["error"]
            throw OpenAIErrors.streamFailure(code: error["code"].text, message: error["message"].string, model: requestedModel, knownSecrets: knownSecrets, requestID: requestID)
        case "error":
            // The documented shape is flat (`code`, `message`); a nested `error` is read too.
            let code = json["code"].text ?? json["error"]["code"].text
            let message = json["message"].string ?? json["error"]["message"].string
            throw OpenAIErrors.streamFailure(code: code, message: message, model: requestedModel, knownSecrets: knownSecrets, requestID: requestID)
        default:
            break
        }
        return false
    }

    /// Whether the completed response's output holds a refusal: a `message` item whose content
    /// has a part of type "refusal" (`ResponseOutputRefusal`) instead of `output_text`. Checked as
    /// well as the streamed events, so a refusal is caught even if none of them arrived.
    static func containsRefusal(_ output: JSONValue) -> Bool {
        output.array.contains { item in
            item["content"].array.contains { $0["type"].string == "refusal" }
        }
    }

    private mutating func startIfNeeded(_ emit: (EngineEvent) -> Void) {
        guard !started else { return }
        started = true
        emit(.started(servedModel: requestedModel, requestID: requestID))
    }
}

extension TokenUsage {
    /// The `usage` object of a finished OpenAI response.
    init(openAI usage: JSONValue) {
        self.init(
            inputTokens: usage["input_tokens"].int,
            outputTokens: usage["output_tokens"].int,
            cacheReadInputTokens: usage["input_tokens_details"]["cached_tokens"].int,
            reasoningTokens: usage["output_tokens_details"]["reasoning_tokens"].int
        )
    }
}
