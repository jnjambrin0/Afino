import Foundation

/// An API that rewrites prompts with the person's own key (BYOK).
public protocol PromptEngineProvider: Sendable {
    /// Which provider this client talks to.
    var id: ProviderID { get }

    /// Sends `request` and streams the answer. Cancelling the consumer (or dropping the stream)
    /// cancels the request, including any back-off wait. Errors are thrown as `EngineFailure`.
    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error>

    /// The models `key` can use. Doubles as key validation (a bad key throws `.invalidKey`) and
    /// spends no tokens.
    func models(key: APIKey) async throws -> [RemoteModel]

    /// Opens a connection to the provider ahead of a request: a `HEAD` without credentials, at
    /// most once a minute. Failures are ignored.
    func prewarm() async
}
