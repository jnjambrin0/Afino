import Foundation
import PICore
import PIProviders

/// What the accent button offers after a run went wrong.
nonisolated enum PanelRecovery: Hashable, Sendable {
    case tryAgain
    case openSettings
    /// Back to the composer with the draft (⌘E).
    case edit
}

/// The tint of a problem's glyph. Never the only signal: a glyph and a line of words go with it.
nonisolated enum PanelProblemTint: Hashable, Sendable {
    case red
    case orange
    case secondary
}

/// The one line that says what happened and what to do.
nonisolated enum PanelProblemLine: Hashable, Sendable {
    case invalidKey(ProviderID?)
    case noKey(ProviderID)
    case noCredit(ProviderID?)
    case modelUnavailable(String)
    /// `seconds` is what is left of the wait the provider asked for; nil when it gave none or
    /// the wait is over.
    case rateLimited(seconds: Int?)
    case overloaded(ProviderID?)
    case serverError(ProviderID?)
    case offline
    case timeout(seconds: Int)
    /// The connection dropped after part of the answer arrived.
    case dropped
    /// The connection dropped before any answer.
    case droppedEarly
    case secureConnection
    case refusal
    case truncated
    /// Cut off at the length limit before any text came.
    case truncatedEmpty
    case emptyOutput
    case malformed(ProviderID?)
    case invalidRequest(ProviderID?)
    case permissionDenied(ProviderID?)
    case contextTooLong
    /// The user stopped a run that had written something.
    case stopped
    case generic

    /// The line's key in `Panel.xcstrings`, so tests can check the catalog has it.
    var key: String {
        switch self {
        case .invalidKey: "error.invalidKey"
        case .noKey: "error.noKey"
        case .noCredit: "error.noCredit"
        case .modelUnavailable: "error.modelUnavailable"
        case .rateLimited(let seconds): seconds == nil ? "error.rateLimitedNow" : "error.rateLimited"
        case .overloaded: "error.overloaded"
        case .serverError: "error.serverError"
        case .offline: "error.offline"
        case .timeout: "error.timeout"
        case .dropped: "error.dropped"
        case .droppedEarly: "error.droppedEarly"
        case .secureConnection: "error.secureConnection"
        case .refusal: "error.refusal"
        case .truncated: "error.truncated"
        case .truncatedEmpty: "error.truncatedEmpty"
        case .emptyOutput: "error.emptyOutput"
        case .malformed: "error.malformed"
        case .invalidRequest: "error.invalidRequest"
        case .permissionDenied: "error.permissionDenied"
        case .contextTooLong: "error.contextTooLong"
        case .stopped: "notice.stopped"
        case .generic: "error.generic"
        }
    }
}

/// How the panel shows a failed or stopped run: in the well when nothing was written, or in a
/// 36 pt notice row under the text that was kept. Nothing partial is ever copied on its own.
nonisolated struct PanelProblemPresentation: Hashable, Sendable {
    enum Placement: Hashable, Sendable {
        /// A glyph and one line inside the well; there is no text.
        case block
        /// A row under the well; the partial text stays above it.
        case notice
    }

    var placement: Placement
    var symbol: String
    var tint: PanelProblemTint
    var line: PanelProblemLine
    var recovery: PanelRecovery
    /// ⌘C copies the text that was kept.
    var offersCopy: Bool { placement == .notice }

    /// The waits a time-out names when the run has no measured duration, per phase (the same
    /// values as `StreamTimeouts.standard`).
    static let headerTimeoutSeconds = 20
    static let idleTimeoutSeconds = 300

    /// How the panel presents `problem`.
    ///
    /// - Parameters:
    ///   - hasText: Whether the run wrote something that is still shown.
    ///   - elapsed: How long the run took, to name a time-out honestly.
    ///   - retryRemaining: Seconds left of a rate limit's wait.
    static func make(
        for problem: SessionProblem,
        hasText: Bool,
        elapsed: TimeInterval? = nil,
        retryRemaining: Int? = nil
    ) -> PanelProblemPresentation {
        let placement: Placement = hasText ? .notice : .block
        switch problem {
        case .truncated:
            return PanelProblemPresentation(
                placement: placement, symbol: "scissors", tint: .orange,
                line: hasText ? .truncated : .truncatedEmpty, recovery: .tryAgain)
        case .refused:
            return PanelProblemPresentation(
                placement: placement, symbol: "hand.raised", tint: .secondary, line: .refusal, recovery: .edit)
        case .emptyOutput:
            return PanelProblemPresentation(
                placement: placement, symbol: "exclamationmark.circle", tint: .orange, line: .emptyOutput, recovery: .tryAgain)
        case let .engine(error, provider, _):
            return make(for: error, provider: provider, placement: placement, elapsed: elapsed, retryRemaining: retryRemaining)
        }
    }

    /// A run the user stopped after it wrote something.
    static var stopped: PanelProblemPresentation {
        PanelProblemPresentation(placement: .notice, symbol: "stop.circle", tint: .secondary, line: .stopped, recovery: .tryAgain)
    }

    private static func make(
        for error: EngineError,
        provider: ProviderID?,
        placement: Placement,
        elapsed: TimeInterval?,
        retryRemaining: Int?
    ) -> PanelProblemPresentation {
        func presentation(_ symbol: String, _ tint: PanelProblemTint, _ line: PanelProblemLine, _ recovery: PanelRecovery) -> PanelProblemPresentation {
            PanelProblemPresentation(placement: placement, symbol: symbol, tint: tint, line: line, recovery: recovery)
        }
        let network = "wifi.slash"
        let server = "exclamationmark.icloud"
        let generic = "exclamationmark.circle"
        switch error {
        case .invalidKey(let keyProvider):
            return presentation("key.slash", .red, .invalidKey(keyProvider), .openSettings)
        case .missingKey(let keyProvider):
            return presentation("key.slash", .red, .noKey(keyProvider), .openSettings)
        case .billing:
            return presentation("creditcard.trianglebadge.exclamationmark", .orange, .noCredit(provider), .tryAgain)
        case .modelNotFound(let model):
            return presentation("questionmark.circle", .orange, .modelUnavailable(model), .openSettings)
        case .rateLimited:
            let seconds = retryRemaining.flatMap { $0 > 0 ? $0 : nil }
            return presentation("hourglass", .orange, .rateLimited(seconds: seconds), .tryAgain)
        case .overloaded:
            return presentation(server, .orange, .overloaded(provider), .tryAgain)
        case .serverError:
            return presentation(server, .orange, .serverError(provider), .tryAgain)
        case .offline:
            return presentation(network, .orange, .offline, .tryAgain)
        case .timedOut(let phase):
            let fallback = phase == .responseHeaders ? headerTimeoutSeconds : idleTimeoutSeconds
            let seconds = elapsed.map { max(1, Int($0.rounded())) } ?? fallback
            return presentation(network, .orange, .timeout(seconds: seconds), .tryAgain)
        case .secureConnection:
            return presentation(network, .orange, .secureConnection, .tryAgain)
        case .connectionLost:
            // What decides the line is whether text is still on screen, not what the transport saw.
            return presentation("wifi.exclamationmark", .orange, placement == .notice ? .dropped : .droppedEarly, .tryAgain)
        case .malformedResponse:
            return presentation(generic, .orange, .malformed(provider), .tryAgain)
        case .invalidRequest:
            return presentation(generic, .orange, .invalidRequest(provider), .edit)
        case .permissionDenied:
            return presentation(generic, .orange, .permissionDenied(provider), .tryAgain)
        case .contextTooLong:
            return presentation(generic, .orange, .contextTooLong, .edit)
        case .cancelled:
            return presentation(generic, .orange, .generic, .tryAgain)
        }
    }

    /// Seconds left of a rate limit's wait at `now`, or nil when there is no wait (or it is over).
    static func retryRemaining(for problem: SessionProblem, endedAt: Date?, now: Date) -> Int? {
        guard case .engine(.rateLimited(let retryAfter?), _, _) = problem, let endedAt else { return nil }
        let wait = Double(retryAfter.components.seconds) + Double(retryAfter.components.attoseconds) / 1e18
        let left = wait - now.timeIntervalSince(endedAt)
        return left > 0 ? Int(left.rounded(.up)) : nil
    }

    /// The error's case for "Copy details": the case and its codes, never a provider message
    /// (which could quote the draft).
    static func caseDescription(of problem: SessionProblem) -> String {
        switch problem {
        case .truncated: return "truncated"
        case .refused(let category): return "refused(\(category ?? "-"))"
        case .emptyOutput: return "emptyOutput"
        case .engine(let error, _, _):
            switch error {
            case .missingKey(let provider): return "missingKey(\(provider.rawValue))"
            case .invalidKey(let provider): return "invalidKey(\(provider.rawValue))"
            case .permissionDenied: return "permissionDenied"
            case .billing: return "billing"
            case .modelNotFound(let model): return "modelNotFound(\(model))"
            case .contextTooLong: return "contextTooLong"
            case .invalidRequest: return "invalidRequest"
            case .rateLimited(let retryAfter):
                return "rateLimited(\(retryAfter.map { "\($0.components.seconds) s" } ?? "-"))"
            case .overloaded: return "overloaded"
            case .serverError(let status): return "serverError(\(status))"
            case .offline: return "offline"
            case .timedOut(let phase): return "timedOut(\(phase.rawValue))"
            case .connectionLost(let receivedText): return "connectionLost(receivedText: \(receivedText))"
            case .secureConnection: return "secureConnection"
            case .malformedResponse: return "malformedResponse"
            case .cancelled: return "cancelled"
            }
        }
    }
}

extension PanelProblemLine {
    /// The line in the interface language.
    var text: String {
        func name(_ provider: ProviderID?) -> String { provider?.displayName ?? PanelStrings.theProvider }
        switch self {
        case .invalidKey(let provider): return PanelStrings.invalidKey(name(provider))
        case .noKey(let provider): return PanelStrings.noKey(provider.displayName)
        case .noCredit(let provider): return PanelStrings.noCredit(name(provider))
        case .modelUnavailable(let model): return PanelStrings.modelUnavailable(model)
        case .rateLimited(let seconds):
            return seconds.map(PanelStrings.rateLimited(seconds:)) ?? PanelStrings.rateLimitedNow
        case .overloaded(let provider): return PanelStrings.overloaded(name(provider))
        case .serverError(let provider): return PanelStrings.serverError(name(provider))
        case .offline: return PanelStrings.offline
        case .timeout(let seconds): return PanelStrings.timeout(seconds: seconds)
        case .dropped: return PanelStrings.dropped
        case .droppedEarly: return PanelStrings.droppedEarly
        case .secureConnection: return PanelStrings.secureConnection
        case .refusal: return PanelStrings.refusal
        case .truncated: return PanelStrings.truncated
        case .truncatedEmpty: return PanelStrings.truncatedEmpty
        case .emptyOutput: return PanelStrings.emptyOutput
        case .malformed(let provider): return PanelStrings.malformed(name(provider))
        case .invalidRequest(let provider): return PanelStrings.invalidRequest(name(provider))
        case .permissionDenied(let provider): return PanelStrings.permissionDenied(name(provider))
        case .contextTooLong: return PanelStrings.contextTooLong
        case .stopped: return PanelStrings.stoppedNotice
        case .generic: return PanelStrings.genericError
        }
    }
}
