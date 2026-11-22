import Foundation
@testable import PIApp
import PICore
import PIProviders
import Testing

/// Every way a run can go wrong → glyph, tint, line and the accent recovery.
struct PanelProblemPresentationTests {
    nonisolated struct Row: Sendable, CustomTestStringConvertible {
        let problem: SessionProblem
        let symbol: String
        let tint: PanelProblemTint
        let key: String
        let recovery: PanelRecovery
        var testDescription: String { key }
    }

    nonisolated private static func engine(_ error: EngineError) -> SessionProblem {
        .engine(error, provider: .anthropic, requestID: "req_1")
    }

    /// Without text, every case is a block in the well.
    nonisolated static let rows: [Row] = [
        Row(problem: engine(.invalidKey(.anthropic)), symbol: "key.slash", tint: .red, key: "error.invalidKey", recovery: .openSettings),
        Row(problem: engine(.missingKey(.openai)), symbol: "key.slash", tint: .red, key: "error.noKey", recovery: .openSettings),
        Row(problem: engine(.billing), symbol: "creditcard.trianglebadge.exclamationmark", tint: .orange, key: "error.noCredit", recovery: .tryAgain),
        Row(problem: engine(.modelNotFound("claude-x")), symbol: "questionmark.circle", tint: .orange, key: "error.modelUnavailable", recovery: .openSettings),
        Row(problem: engine(.rateLimited(retryAfter: nil)), symbol: "hourglass", tint: .orange, key: "error.rateLimitedNow", recovery: .tryAgain),
        Row(problem: engine(.overloaded), symbol: "exclamationmark.icloud", tint: .orange, key: "error.overloaded", recovery: .tryAgain),
        Row(problem: engine(.serverError(status: 503)), symbol: "exclamationmark.icloud", tint: .orange, key: "error.serverError", recovery: .tryAgain),
        Row(problem: engine(.offline), symbol: "wifi.slash", tint: .orange, key: "error.offline", recovery: .tryAgain),
        Row(problem: engine(.timedOut(.responseHeaders)), symbol: "wifi.slash", tint: .orange, key: "error.timeout", recovery: .tryAgain),
        Row(problem: engine(.timedOut(.idle)), symbol: "wifi.slash", tint: .orange, key: "error.timeout", recovery: .tryAgain),
        Row(problem: engine(.secureConnection), symbol: "wifi.slash", tint: .orange, key: "error.secureConnection", recovery: .tryAgain),
        Row(problem: engine(.connectionLost(receivedText: false)), symbol: "wifi.exclamationmark", tint: .orange, key: "error.droppedEarly", recovery: .tryAgain),
        Row(problem: engine(.malformedResponse), symbol: "exclamationmark.circle", tint: .orange, key: "error.malformed", recovery: .tryAgain),
        Row(problem: engine(.invalidRequest("secret draft words")), symbol: "exclamationmark.circle", tint: .orange, key: "error.invalidRequest", recovery: .edit),
        Row(problem: engine(.permissionDenied), symbol: "exclamationmark.circle", tint: .orange, key: "error.permissionDenied", recovery: .tryAgain),
        Row(problem: engine(.contextTooLong), symbol: "exclamationmark.circle", tint: .orange, key: "error.contextTooLong", recovery: .edit),
        Row(problem: engine(.cancelled), symbol: "exclamationmark.circle", tint: .orange, key: "error.generic", recovery: .tryAgain),
        Row(problem: .refused(category: "cyber"), symbol: "hand.raised", tint: .secondary, key: "error.refusal", recovery: .edit),
        Row(problem: .emptyOutput, symbol: "exclamationmark.circle", tint: .orange, key: "error.emptyOutput", recovery: .tryAgain),
        Row(problem: .truncated, symbol: "scissors", tint: .orange, key: "error.truncatedEmpty", recovery: .tryAgain),
    ]

    @Test(arguments: rows)
    func everyProblemWithoutTextIsABlockInTheWell(row: Row) {
        let presentation = PanelProblemPresentation.make(for: row.problem, hasText: false)
        #expect(presentation.placement == .block)
        #expect(presentation.symbol == row.symbol)
        #expect(presentation.tint == row.tint)
        #expect(presentation.line.key == row.key)
        #expect(presentation.recovery == row.recovery)
        #expect(!presentation.offersCopy)
    }

    @Test func everyEngineErrorCaseIsCovered() {
        // A new EngineError case must be added to `rows` (and given a line).
        let cases: [EngineError] = [
            .missingKey(.anthropic), .invalidKey(.anthropic), .permissionDenied, .billing, .modelNotFound(""),
            .contextTooLong, .invalidRequest(""), .rateLimited(retryAfter: nil), .overloaded, .serverError(status: 500),
            .offline, .timedOut(.idle), .connectionLost(receivedText: true), .secureConnection, .malformedResponse, .cancelled,
        ]
        for error in cases {
            let name = "\(error)".prefix { $0 != "(" }
            #expect(Self.rows.contains { "\($0.problem)".contains(name) }, "\(name)")
        }
    }

    // MARK: With text: a notice row, copy offered, nothing copied

    @Test func aDroppedConnectionAfterTextIsANoticeWithCopy() {
        let presentation = PanelProblemPresentation.make(for: Self.engine(.connectionLost(receivedText: true)), hasText: true)
        #expect(presentation.placement == .notice)
        #expect(presentation.symbol == "wifi.exclamationmark")
        #expect(presentation.line == .dropped)
        #expect(presentation.recovery == .tryAgain)
        #expect(presentation.offersCopy)
    }

    @Test func aTruncatedResultKeepsItsTextWithANotice() {
        let presentation = PanelProblemPresentation.make(for: .truncated, hasText: true)
        #expect(presentation.placement == .notice)
        #expect(presentation.symbol == "scissors")
        #expect(presentation.line == .truncated)
        #expect(presentation.recovery == .tryAgain)
        #expect(presentation.offersCopy)
    }

    @Test func anyFailureAfterTextMovesToTheNoticeRow() {
        let presentation = PanelProblemPresentation.make(for: Self.engine(.overloaded), hasText: true)
        #expect(presentation.placement == .notice)
        #expect(presentation.symbol == "exclamationmark.icloud")
        #expect(presentation.line == .overloaded(.anthropic))
    }

    @Test func aStoppedRunIsANoticeThatOffersTryAgain() {
        let presentation = PanelProblemPresentation.stopped
        #expect(presentation.placement == .notice)
        #expect(presentation.line.key == "notice.stopped")
        #expect(presentation.recovery == .tryAgain)
        #expect(presentation.offersCopy)
    }

    // MARK: Lines with numbers

    @Test func aRateLimitCountsDownAndNeverFiresOnItsOwn() {
        let ended = Date(timeIntervalSince1970: 1_000)
        let problem = Self.engine(.rateLimited(retryAfter: .seconds(12)))
        #expect(PanelProblemPresentation.retryRemaining(for: problem, endedAt: ended, now: ended) == 12)
        #expect(PanelProblemPresentation.retryRemaining(for: problem, endedAt: ended, now: ended.addingTimeInterval(4.2)) == 8)
        #expect(PanelProblemPresentation.retryRemaining(for: problem, endedAt: ended, now: ended.addingTimeInterval(12)) == nil)
        #expect(PanelProblemPresentation.retryRemaining(for: Self.engine(.rateLimited(retryAfter: nil)), endedAt: ended, now: ended) == nil)
        #expect(PanelProblemPresentation.retryRemaining(for: Self.engine(.overloaded), endedAt: ended, now: ended) == nil)

        let waiting = PanelProblemPresentation.make(for: problem, hasText: false, retryRemaining: 8)
        #expect(waiting.line == .rateLimited(seconds: 8))
        #expect(waiting.line.key == "error.rateLimited")
        let over = PanelProblemPresentation.make(for: problem, hasText: false, retryRemaining: nil)
        #expect(over.line.key == "error.rateLimitedNow")
    }

    @Test func aTimeoutNamesHowLongItReallyWaited() {
        let headers = Self.engine(.timedOut(.responseHeaders))
        #expect(PanelProblemPresentation.make(for: headers, hasText: false).line == .timeout(seconds: 20))
        #expect(PanelProblemPresentation.make(for: headers, hasText: false, elapsed: 61.6).line == .timeout(seconds: 62))
        #expect(PanelProblemPresentation.make(for: Self.engine(.timedOut(.idle)), hasText: false).line == .timeout(seconds: 300))
    }

    @Test func linesNameTheProviderAndTheModel() {
        #expect(PanelProblemPresentation.make(for: Self.engine(.invalidKey(.openai)), hasText: false).line == .invalidKey(.openai))
        #expect(PanelProblemPresentation.make(for: Self.engine(.modelNotFound("gpt-x")), hasText: false).line == .modelUnavailable("gpt-x"))
        let unknown = PanelProblemPresentation.make(for: .engine(.billing, provider: nil, requestID: nil), hasText: false)
        #expect(unknown.line == .noCredit(nil))
    }

    @Test func theLinesReadInTheInterfaceLanguageWithTheirValues() {
        #expect(PanelProblemLine.invalidKey(.anthropic).text.contains("Anthropic"))
        #expect(PanelProblemLine.modelUnavailable("gpt-x").text.contains("gpt-x"))
        #expect(PanelProblemLine.rateLimited(seconds: 8).text.contains("8"))
        #expect(PanelProblemLine.timeout(seconds: 20).text.contains("20"))
        #expect(!PanelProblemLine.overloaded(nil).text.contains("%@"))
    }

    // MARK: Copy details

    @Test func copyDetailsNamesTheCaseButNeverAProviderMessage() {
        #expect(PanelProblemPresentation.caseDescription(of: Self.engine(.invalidRequest("secret draft words"))) == "invalidRequest")
        #expect(PanelProblemPresentation.caseDescription(of: Self.engine(.serverError(status: 529))) == "serverError(529)")
        #expect(PanelProblemPresentation.caseDescription(of: Self.engine(.rateLimited(retryAfter: .seconds(12)))) == "rateLimited(12 s)")
        #expect(PanelProblemPresentation.caseDescription(of: .refused(category: nil)) == "refused(-)")
        #expect(PanelProblemPresentation.caseDescription(of: .truncated) == "truncated")
    }
}
