import Foundation
import PIFoundation
import os

/// The Messages API stream as `EngineEvent`s, dispatched on each event's JSON `type`.
///
/// - `message_start` → `.started` (the model from `message.model`, the id from `request-id`)
/// - `content_block_start` of a `thinking` / `redacted_thinking` block → `.thinking`
/// - `content_block_delta` with a `text_delta` → `.textDelta`
/// - `message_delta` → remembers `stop_reason`, `stop_details` and `usage`
/// - `message_stop` → `.finished`
/// - `error` → throws; `ping`, `content_block_stop` and unknown types are ignored
///
/// Server-side fallback: a `fallback` block marks where another model took over. Anthropic's
/// streaming documentation (Refusals and fallback › Streaming, checked 2026-11-21) says the
/// retry happens on the same stream, "nothing you have already received is invalidated", and
/// "the fallback model continues from the partial output". So the block is only logged and the
/// text keeps accumulating. Before any output, `message_start` already names the fallback model.
struct AnthropicStreamHandler: SSEStreamHandler {
    let requestedModel: String
    let knownSecrets: [String]
    private var requestID: String?
    private var started = false
    private var stopReason: String?
    private var refusalCategory: String?
    private var usage = TokenUsage()

    private static let logger = Log.logger(.engine)

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
        case "message_start":
            usage.merge(anthropic: json["message"]["usage"])
            started = true
            emit(.started(servedModel: json["message"]["model"].string ?? requestedModel, requestID: requestID))
        case "content_block_start":
            switch json["content_block"]["type"].string {
            case "thinking", "redacted_thinking":
                startIfNeeded(emit)
                emit(.thinking)
            case "fallback":
                let block = json["content_block"]
                let from = block["from"]["model"].string ?? "?"
                let to = block["to"]["model"].string ?? "?"
                let category = block["trigger"]["category"].string ?? "no category"
                let request = requestID ?? "-"
                Self.logger.info("Server-side fallback from \(from, privacy: .public) to \(to, privacy: .public) (\(category, privacy: .public)), request \(request, privacy: .public)")
            default:
                break
            }
        case "content_block_delta":
            guard json["delta"]["type"].string == "text_delta", let text = json["delta"]["text"].string, !text.isEmpty else { break }
            startIfNeeded(emit)
            emit(.textDelta(text))
        case "message_delta":
            if let reason = json["delta"]["stop_reason"].string { stopReason = reason }
            // The schema puts stop_details in `delta`; the top level is read too in case it moves.
            let details = json["delta"]["stop_details"].isObject ? json["delta"]["stop_details"] : json["stop_details"]
            if let category = details["category"].string { refusalCategory = category }
            usage.merge(anthropic: json["usage"])
        case "message_stop":
            startIfNeeded(emit)
            emit(.finished(finishReason, usage: usage.nonEmpty))
            return true
        case "error":
            throw AnthropicErrors.streamFailure(json, model: requestedModel, knownSecrets: knownSecrets, requestID: requestID)
        default:
            break
        }
        return false
    }

    var finishReason: FinishReason {
        switch stopReason {
        case "max_tokens", "model_context_window_exceeded": .truncated
        case "refusal": .refused(category: refusalCategory)
        default: .complete // end_turn, stop_sequence, and anything else that ended the turn
        }
    }

    /// A stream that skipped `message_start` still reports `.started` before anything else.
    private mutating func startIfNeeded(_ emit: (EngineEvent) -> Void) {
        guard !started else { return }
        started = true
        emit(.started(servedModel: requestedModel, requestID: requestID))
    }
}

extension TokenUsage {
    /// Anthropic's counts are cumulative: a later value replaces an earlier one.
    mutating func merge(anthropic usage: JSONValue) {
        if let value = usage["input_tokens"].int { inputTokens = value }
        if let value = usage["output_tokens"].int { outputTokens = value }
        if let value = usage["cache_read_input_tokens"].int { cacheReadInputTokens = value }
        if let value = usage["cache_creation_input_tokens"].int { cacheCreationInputTokens = value }
    }
}
