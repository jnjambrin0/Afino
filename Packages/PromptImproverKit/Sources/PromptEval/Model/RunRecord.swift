import Foundation
import PIProviders

/// The outcome of one deterministic check.
struct CheckResult: Codable, Sendable, Hashable {
    var name: String
    var passed: Bool
    var detail: String

    static func pass(_ name: String, _ detail: String = "") -> CheckResult {
        CheckResult(name: name, passed: true, detail: detail)
    }

    static func fail(_ name: String, _ detail: String) -> CheckResult {
        CheckResult(name: name, passed: false, detail: detail)
    }
}

/// Token counts as the provider reported them (any of them may be missing).
struct UsageRecord: Codable, Sendable, Hashable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadInputTokens: Int?
    var cacheCreationInputTokens: Int?
    var reasoningTokens: Int?

    init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.reasoningTokens = reasoningTokens
    }

    init(_ usage: TokenUsage) {
        self.init(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadInputTokens: usage.cacheReadInputTokens,
            cacheCreationInputTokens: usage.cacheCreationInputTokens,
            reasoningTokens: usage.reasoningTokens
        )
    }
}

/// A failed request, by `EngineError` case name. Provider messages are left out on purpose: they
/// can quote the request, and the request holds the draft.
struct ErrorRecord: Codable, Sendable, Hashable {
    var name: String
    var requestID: String?
    var httpStatus: Int?

    init(name: String, requestID: String? = nil, httpStatus: Int? = nil) {
        self.name = name
        self.requestID = requestID
        self.httpStatus = httpStatus
    }

    init(_ failure: EngineFailure) {
        self.init(name: Self.caseName(failure.error), requestID: failure.requestID, httpStatus: failure.httpStatus)
    }

    /// The case without any provider text.
    static func caseName(_ error: EngineError) -> String {
        switch error {
        case .missingKey(let provider): "missingKey(\(provider.rawValue))"
        case .invalidKey(let provider): "invalidKey(\(provider.rawValue))"
        case .permissionDenied: "permissionDenied"
        case .billing: "billing"
        case .modelNotFound(let model): "modelNotFound(\(model))"
        case .contextTooLong: "contextTooLong"
        case .invalidRequest: "invalidRequest"
        case .rateLimited: "rateLimited"
        case .overloaded: "overloaded"
        case .serverError(let status): "serverError(\(status))"
        case .offline: "offline"
        case .timedOut(let phase): "timedOut(\(phase.rawValue))"
        case .connectionLost(let receivedText): "connectionLost(receivedText: \(receivedText))"
        case .secureConnection: "secureConnection"
        case .malformedResponse: "malformedResponse"
        case .cancelled: "cancelled"
        }
    }
}

/// What one request did, timed from the moment it was handed to the provider.
struct TurnMeasurement: Codable, Sendable, Hashable {
    /// Seconds to the first event of any kind.
    var timeToFirstEvent: Double?
    /// Seconds to the first text delta.
    var timeToFirstText: Double?
    /// Seconds to the end of the stream (or the failure).
    var totalTime: Double
    /// Characters of the shown (post-processed) output.
    var outputCharacters: Int
    var usage: UsageRecord?
    var retries: Int
    var servedModel: String?
    var requestID: String?
    /// `complete`, `truncated`, `refused` or `refused(<category>)`; nil when the stream ended
    /// without one (or failed).
    var finishReason: String?
    var error: ErrorRecord?
    /// Whether `OutputPostProcessor` removed a code fence around the whole reply.
    var unwrappedFence: Bool
    /// Whether `OutputPostProcessor` removed a preface line such as "Here is the prompt:".
    var strippedPreface: Bool

    init(
        timeToFirstEvent: Double? = nil,
        timeToFirstText: Double? = nil,
        totalTime: Double = 0,
        outputCharacters: Int = 0,
        usage: UsageRecord? = nil,
        retries: Int = 0,
        servedModel: String? = nil,
        requestID: String? = nil,
        finishReason: String? = nil,
        error: ErrorRecord? = nil,
        unwrappedFence: Bool = false,
        strippedPreface: Bool = false
    ) {
        self.timeToFirstEvent = timeToFirstEvent
        self.timeToFirstText = timeToFirstText
        self.totalTime = totalTime
        self.outputCharacters = outputCharacters
        self.usage = usage
        self.retries = retries
        self.servedModel = servedModel
        self.requestID = requestID
        self.finishReason = finishReason
        self.error = error
        self.unwrappedFence = unwrappedFence
        self.strippedPreface = strippedPreface
    }

    static let complete = "complete"

    /// How `finishReason` stores a `FinishReason`.
    static func finishName(_ reason: FinishReason) -> String {
        switch reason {
        case .complete: complete
        case .truncated: "truncated"
        case .refused(let category): category.map { "refused(\($0))" } ?? "refused"
        }
    }

    var isComplete: Bool { error == nil && finishReason == Self.complete }

    /// Why the request did not complete, or nil when it did.
    var failureDescription: String? {
        if let error {
            return error.name + (error.requestID.map { " [request \($0)]" } ?? "")
        }
        guard let finishReason else { return "stream ended without a finish event" }
        return finishReason == Self.complete ? nil : "finished as \(finishReason)"
    }
}

/// One request of a run: the first rewrite, or the refinement after it.
struct TurnRecord: Codable, Sendable, Hashable {
    /// The revision request for a refinement turn; nil for the first turn.
    var instruction: String?
    var measurement: TurnMeasurement
}

/// One criterion as the judge answered it.
struct CriterionVerdict: Codable, Sendable, Hashable {
    var passed: Bool
    var reason: String
}

/// One judge model's grading of one output.
struct JudgeVerdict: Codable, Sendable, Hashable {
    var provider: ProviderID
    var model: String
    /// Keyed by the names in `RubricJudge.criteria`.
    var criteria: [String: CriterionVerdict]
    /// The overall score from 1 to 5; nil when the judge produced none.
    var overall: Int?
    /// Why the judge produced no usable grade (request failed, unparseable reply).
    var error: String?
    var usage: UsageRecord?

    var isUsable: Bool { error == nil && overall != nil }
}

/// The primary judge and, for a sample, the cross-check from another model family.
struct JudgeOutcome: Codable, Sendable, Hashable {
    var primary: JudgeVerdict
    var crossCheck: JudgeVerdict?
}

/// One line of `results.jsonl`: a fixture run once on one configuration.
struct RunRecord: Codable, Sendable, Hashable {
    var fixtureID: String
    var configuration: EvalConfiguration
    var repetition: Int
    /// The `<draft>` id of the run (needed to check it never leaks; random, not sensitive).
    var draftID: String
    var turns: [TurnRecord]
    /// Refinements only: the output of the first turn, which the revision request applied to.
    var firstOutput: String?
    /// The shown output of the last turn that ran, post-processed as the app shows it.
    var output: String
    var checks: [CheckResult]
    var judge: JudgeOutcome?
    var startedAt: Date

    /// Why the run did not complete, or nil when every turn did.
    var completionFailure: String? {
        guard !turns.isEmpty else { return "no request was sent" }
        for (index, turn) in turns.enumerated() {
            if let failure = turn.measurement.failureDescription {
                return turns.count > 1 ? "turn \(index + 1): \(failure)" : failure
            }
        }
        return nil
    }

    var deterministicPassed: Bool { checks.allSatisfy(\.passed) }
    var failedChecks: [CheckResult] { checks.filter { !$0.passed } }
}

/// Assertions made once per configuration rather than per run.
struct ConfigurationCheck: Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable {
        case pass
        /// Fails the gate for the configuration.
        case fail
        /// Shown in the summary; does not affect the gate.
        case warning
    }

    var configurationID: String
    var name: String
    var status: Status
    var detail: String
}

/// `run.json`: how a results folder was produced.
struct RunInfo: Codable, Sendable, Hashable {
    var mode: String
    var startedAt: Date
    var finishedAt: Date?
    var repetitions: Int
    var fixtureIDs: [String]
    var configurations: [EvalConfiguration]
    var judgeModel: String?
    var crossCheckModel: String?
}
