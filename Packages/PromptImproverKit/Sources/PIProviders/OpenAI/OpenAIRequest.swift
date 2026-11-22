import Foundation

/// The Responses API request for an `EngineRequest`.
///
/// Sends exactly: `model`, `stream`, `store: false`, `max_output_tokens`, `reasoning.effort`
/// when an effort is set (`none` included), and `input` with the system text as the first
/// item (`developer`, all blocks joined by a blank line) followed by the turns (`input_text`
/// for the user, `output_text` for the assistant). Never top-level `instructions`,
/// `temperature`, `top_p` or `previous_response_id`; `thinkingDisabled` and
/// `serverSideFallback` are Anthropic's and ignored.
enum OpenAIRequest {
    struct Body: Encodable, Equatable {
        struct Reasoning: Encodable, Equatable {
            var effort: String
        }

        struct Content: Encodable, Equatable {
            var type: String
            var text: String
        }

        struct Item: Encodable, Equatable {
            var role: String
            var content: [Content]
        }

        var model: String
        var stream = true
        var store = false
        var maxOutputTokens: Int
        var reasoning: Reasoning?
        var input: [Item]
    }

    static func body(for request: EngineRequest) throws(EngineFailure) -> Body {
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw EngineFailure(.invalidRequest("No model is selected."), provider: .openai)
        }
        var input: [Body.Item] = []
        let system = request.systemBlocks
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty {
            input.append(Body.Item(role: "developer", content: [Body.Content(type: "input_text", text: system)]))
        }
        var turns = request.turns
        while case .assistant = turns.last { turns.removeLast() }
        guard !turns.isEmpty else {
            throw EngineFailure(.invalidRequest("There is nothing to send."), provider: .openai)
        }
        for turn in turns {
            switch turn {
            case let .user(text):
                input.append(Body.Item(role: "user", content: [Body.Content(type: "input_text", text: text)]))
            case let .assistant(text):
                input.append(Body.Item(role: "assistant", content: [Body.Content(type: "output_text", text: text)]))
            }
        }
        return Body(
            model: model,
            maxOutputTokens: max(1, request.maxOutputTokens),
            reasoning: request.effort.map { Body.Reasoning(effort: $0.rawValue) },
            input: input
        )
    }

    static func encode(_ body: Body) throws(EngineFailure) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(body)
        } catch {
            throw EngineFailure(.invalidRequest("The request could not be encoded."), provider: .openai)
        }
    }

    static func urlRequest(for request: EngineRequest, key: APIKey, baseURL: URL) throws(EngineFailure) -> URLRequest {
        guard !key.isEmpty else { throw EngineFailure(.missingKey(.openai), provider: .openai) }
        let body = try body(for: request)
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/responses"))
        urlRequest.httpMethod = "POST"
        setAuthorization(on: &urlRequest, key: key)
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.httpBody = try encode(body)
        return urlRequest
    }

    static func setAuthorization(on request: inout URLRequest, key: APIKey) {
        request.setValue("Bearer \(key.rawValue)", forHTTPHeaderField: "authorization")
    }
}
