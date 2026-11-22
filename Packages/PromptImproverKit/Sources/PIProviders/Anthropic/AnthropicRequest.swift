import Foundation

/// The Messages API request for an `EngineRequest`.
///
/// Sends exactly: `model`, `max_tokens`, `stream`, `system` as text blocks with the cache
/// breakpoint on the last one, `messages` as text turns ending with the user's, `output_config`
/// only for an effort other than `none`, `thinking: {type: "disabled"}` only when asked, and
/// `fallbacks: "default"` (with its beta header) only when asked. Never `temperature`, `top_p`,
/// `top_k`, `budget_tokens` or a trailing assistant turn (prefill).
enum AnthropicRequest {
    struct Body: Encodable, Equatable {
        struct CacheControl: Encodable, Equatable {
            var type = "ephemeral"
        }

        struct SystemBlock: Encodable, Equatable {
            var type = "text"
            var text: String
            var cacheControl: CacheControl?
        }

        struct Message: Encodable, Equatable {
            var role: String
            var content: String
        }

        struct OutputConfig: Encodable, Equatable {
            var effort: String
        }

        struct Thinking: Encodable, Equatable {
            var type: String
        }

        var model: String
        var maxTokens: Int
        var stream = true
        var system: [SystemBlock]?
        var messages: [Message]
        var outputConfig: OutputConfig?
        var thinking: Thinking?
        var fallbacks: String?
    }

    static func body(for request: EngineRequest) throws(EngineFailure) -> Body {
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw EngineFailure(.invalidRequest("No model is selected."), provider: .anthropic)
        }
        let blocks = request.systemBlocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let system = blocks.enumerated().map { index, text in
            Body.SystemBlock(text: text, cacheControl: index == blocks.count - 1 ? Body.CacheControl() : nil)
        }
        let messages = try messages(from: request.turns)
        let effort = request.effort.flatMap { $0 == .none ? nil : Body.OutputConfig(effort: $0.rawValue) }
        return Body(
            model: model,
            maxTokens: max(1, request.maxOutputTokens),
            system: system.isEmpty ? nil : system,
            messages: messages,
            outputConfig: effort,
            thinking: request.thinkingDisabled ? Body.Thinking(type: "disabled") : nil,
            fallbacks: request.serverSideFallback ? "default" : nil
        )
    }

    /// The turns without a trailing assistant turn; at least one user turn must remain.
    static func messages(from turns: [EngineRequest.Turn]) throws(EngineFailure) -> [Body.Message] {
        var messages = turns.map { turn in
            switch turn {
            case let .user(text): Body.Message(role: "user", content: text)
            case let .assistant(text): Body.Message(role: "assistant", content: text)
            }
        }
        while messages.last?.role == "assistant" { messages.removeLast() }
        guard !messages.isEmpty else {
            throw EngineFailure(.invalidRequest("There is nothing to send."), provider: .anthropic)
        }
        return messages
    }

    static func encode(_ body: Body) throws(EngineFailure) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(body)
        } catch {
            throw EngineFailure(.invalidRequest("The request could not be encoded."), provider: .anthropic)
        }
    }

    static func urlRequest(for request: EngineRequest, key: APIKey, baseURL: URL) throws(EngineFailure) -> URLRequest {
        guard !key.isEmpty else { throw EngineFailure(.missingKey(.anthropic), provider: .anthropic) }
        let body = try body(for: request)
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/messages"))
        urlRequest.httpMethod = "POST"
        setCommonHeaders(on: &urlRequest, key: key)
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        if body.fallbacks != nil {
            urlRequest.setValue(AnthropicProvider.serverSideFallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try encode(body)
        return urlRequest
    }

    static func setCommonHeaders(on request: inout URLRequest, key: APIKey) {
        request.setValue(key.rawValue, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicProvider.apiVersion, forHTTPHeaderField: "anthropic-version")
    }
}
