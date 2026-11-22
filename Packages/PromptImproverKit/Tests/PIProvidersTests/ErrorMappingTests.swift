import Foundation
import Testing
@testable import PIProviders

/// One row of an HTTP error table.
struct ErrorCase: Sendable, CustomTestStringConvertible {
    var status: Int
    /// A fixture path, or an inline body.
    var fixture: String?
    var body: String = ""
    var headers: [String: String] = [:]
    var expected: EngineError
    var retryable: Bool

    func response(requestIDHeader: String) throws -> HTTPErrorResponse {
        let data = try fixture.map(Fixture.data) ?? Data(body.utf8)
        return HTTPErrorResponse(head: ResponseHead(status: status, headers: headers, requestIDHeader: requestIDHeader), body: data)
    }

    var testDescription: String { "\(status) \(fixture ?? "inline") → \(expected)" }
}

struct ErrorMappingTests {
    static let anthropicTable: [ErrorCase] = [
        ErrorCase(status: 400, fixture: "anthropic/error_400.json", expected: .invalidRequest("messages.0.content: text content blocks must be non-empty"), retryable: false),
        ErrorCase(status: 400, fixture: "anthropic/error_400_prompt_too_long.json", expected: .contextTooLong, retryable: false),
        ErrorCase(status: 400, fixture: "anthropic/error_400_spend_limit.json", expected: .billing, retryable: false),
        ErrorCase(status: 401, fixture: "anthropic/error_401.json", expected: .invalidKey(.anthropic), retryable: false),
        ErrorCase(status: 402, fixture: "anthropic/error_402.json", expected: .billing, retryable: false),
        ErrorCase(status: 403, body: #"{"type":"error","error":{"type":"permission_error","message":"Your API key does not have permission to use the specified resource."}}"#, expected: .permissionDenied, retryable: false),
        ErrorCase(status: 404, fixture: "anthropic/error_404.json", expected: .modelNotFound("claude-sonnet-5-5"), retryable: false),
        ErrorCase(status: 413, body: #"{"type":"error","error":{"type":"request_too_large","message":"Request exceeds the maximum allowed number of bytes."}}"#, expected: .contextTooLong, retryable: false),
        ErrorCase(status: 422, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Unprocessable"}}"#, expected: .invalidRequest("Unprocessable"), retryable: false),
        ErrorCase(status: 429, fixture: "anthropic/error_429_retry_after.json", headers: ["retry-after": "7"], expected: .rateLimited(retryAfter: .seconds(7)), retryable: true),
        ErrorCase(status: 429, fixture: "anthropic/error_429_spend_cap.json", expected: .billing, retryable: false),
        ErrorCase(status: 408, body: "", expected: .serverError(status: 408), retryable: true),
        ErrorCase(status: 409, body: #"{"type":"error","error":{"type":"conflict_error","message":"Conflict"}}"#, expected: .serverError(status: 409), retryable: true),
        ErrorCase(status: 500, fixture: "anthropic/error_500.json", expected: .serverError(status: 500), retryable: true),
        ErrorCase(status: 502, body: "<html>Bad gateway</html>", expected: .serverError(status: 502), retryable: true),
        ErrorCase(status: 503, body: "", expected: .overloaded, retryable: true),
        ErrorCase(status: 504, body: #"{"type":"error","error":{"type":"timeout_error","message":"Request timed out"}}"#, expected: .serverError(status: 504), retryable: true),
        ErrorCase(status: 529, fixture: "anthropic/error_529.json", expected: .overloaded, retryable: true),
        ErrorCase(status: 500, fixture: "anthropic/error_529.json", expected: .overloaded, retryable: true),
    ]

    @Test(arguments: anthropicTable)
    func anthropicHTTPErrors(_ row: ErrorCase) throws {
        let failure = AnthropicErrors.failure(for: try row.response(requestIDHeader: "request-id"), model: "claude-sonnet-5-5", knownSecrets: [testKey.rawValue])
        #expect(failure.error == row.expected)
        #expect(failure.retryable == row.retryable)
        #expect(failure.httpStatus == row.status)
    }

    @Test func anthropicRequestIDComesFromTheHeaderOrTheBody() throws {
        let body = try Fixture.data("anthropic/error_401.json")
        let fromBody = AnthropicErrors.failure(for: HTTPErrorResponse(head: ResponseHead(status: 401, headers: [:], requestIDHeader: "request-id"), body: body), model: "m", knownSecrets: [])
        #expect(fromBody.requestID == "req_011CAnth401")
        let fromHeader = AnthropicErrors.failure(for: HTTPErrorResponse(head: ResponseHead(status: 401, headers: ["Request-Id": "req_header"], requestIDHeader: "request-id"), body: body), model: "m", knownSecrets: [])
        #expect(fromHeader.requestID == "req_header")
    }

    static let openAITable: [ErrorCase] = [
        ErrorCase(status: 401, fixture: "openai/error_401.json", expected: .invalidKey(.openai), retryable: false),
        ErrorCase(status: 403, body: #"{"error":{"message":"Country, region, or territory not supported","type":"request_forbidden","param":null,"code":"unsupported_country_region_territory"}}"#, expected: .permissionDenied, retryable: false),
        ErrorCase(status: 404, fixture: "openai/error_404.json", expected: .modelNotFound("gpt-6.2-sol"), retryable: false),
        ErrorCase(status: 400, body: #"{"error":{"message":"The model does not exist","type":"invalid_request_error","param":"model","code":"model_not_found"}}"#, expected: .modelNotFound("gpt-6.2-sol"), retryable: false),
        ErrorCase(status: 400, fixture: "openai/error_400_context.json", expected: .contextTooLong, retryable: false),
        ErrorCase(status: 400, body: #"{"error":{"message":"Unsupported parameter: 'foo'.","type":"invalid_request_error","param":"foo","code":"unsupported_parameter"}}"#, expected: .invalidRequest("Unsupported parameter: 'foo'."), retryable: false),
        ErrorCase(status: 429, fixture: "openai/error_429_rate.json", headers: ["retry-after-ms": "120"], expected: .rateLimited(retryAfter: .milliseconds(120)), retryable: true),
        ErrorCase(status: 429, fixture: "openai/error_429_billing.json", expected: .billing, retryable: false),
        ErrorCase(status: 503, fixture: "openai/error_503.json", expected: .overloaded, retryable: true),
        ErrorCase(status: 500, body: #"{"error":{"message":"The server had an error","type":"server_error","param":null,"code":null}}"#, expected: .serverError(status: 500), retryable: true),
        ErrorCase(status: 502, body: "", expected: .serverError(status: 502), retryable: true),
        ErrorCase(status: 504, body: "", expected: .serverError(status: 504), retryable: true),
        ErrorCase(status: 408, body: "", expected: .serverError(status: 408), retryable: true),
    ]

    @Test(arguments: openAITable)
    func openAIHTTPErrors(_ row: ErrorCase) throws {
        let failure = OpenAIErrors.failure(for: try row.response(requestIDHeader: "x-request-id"), model: "gpt-6.2-sol", knownSecrets: [testOpenAIKey.rawValue])
        #expect(failure.error == row.expected)
        #expect(failure.retryable == row.retryable)
    }

    @Test(arguments: OpenAIErrors.billingCodes.sorted(), [true, false])
    func everyOpenAIBillingCodeIsBilling(_ code: String, asType: Bool) {
        let inner = asType ? #""type":"\#(code)","code":null"# : #""type":"requests","code":"\#(code)""#
        let body = Data(#"{"error":{"message":"Out of credit",\#(inner)}}"#.utf8)
        let failure = OpenAIErrors.failure(for: HTTPErrorResponse(head: ResponseHead(status: 429, headers: [:], requestIDHeader: "x-request-id"), body: body), model: "m", knownSecrets: [])
        #expect(failure.error == .billing)
        #expect(!failure.retryable)
    }

    @Test(arguments: [
        ("overloaded_error", EngineError.overloaded, true),
        ("api_error", .serverError(status: 500), true),
        ("timeout_error", .serverError(status: 504), true),
        ("rate_limit_error", .rateLimited(retryAfter: nil), false),
        ("authentication_error", .invalidKey(.anthropic), false),
        ("permission_error", .permissionDenied, false),
        ("billing_error", .billing, false),
        ("not_found_error", .modelNotFound("claude-sonnet-5-5"), false),
        ("request_too_large", .contextTooLong, false),
        ("invalid_request_error", .invalidRequest("Bad"), false),
        ("brand_new_error", .serverError(status: 500), true),
    ])
    func anthropicStreamErrorEvents(_ type: String, _ expected: EngineError, _ retryable: Bool) throws {
        let json = try JSONValue(parsing: #"{"type":"error","error":{"type":"\#(type)","message":"Bad"}}"#)
        let failure = AnthropicErrors.streamFailure(json, model: "claude-sonnet-5-5", knownSecrets: [], requestID: "req_1")
        #expect(failure.error == expected)
        #expect(failure.retryable == retryable)
        #expect(failure.requestID == "req_1")
    }

    @Test(arguments: [
        ("server_error", EngineError.serverError(status: 500), true),
        (nil, .serverError(status: 500), true),
        ("server_is_overloaded", .overloaded, true),
        ("rate_limit_exceeded", .rateLimited(retryAfter: nil), false),
        ("insufficient_quota", .billing, false),
        ("invalid_api_key", .invalidKey(.openai), false),
        ("model_not_found", .modelNotFound("gpt-6.2-sol"), false),
        ("context_length_exceeded", .contextTooLong, false),
        ("invalid_prompt", .invalidRequest("Bad"), false),
    ] as [(String?, EngineError, Bool)])
    func openAIStreamFailures(_ code: String?, _ expected: EngineError, _ retryable: Bool) {
        let failure = OpenAIErrors.streamFailure(code: code, message: "Bad", model: "gpt-6.2-sol", knownSecrets: [], requestID: nil)
        #expect(failure.error == expected)
        #expect(failure.retryable == retryable)
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, EngineError.offline),
        (.dataNotAllowed, .offline),
        (.cannotFindHost, .offline),
        (.cannotConnectToHost, .offline),
        (.timedOut, .timedOut(.responseHeaders)),
        (.secureConnectionFailed, .secureConnection),
        (.serverCertificateUntrusted, .secureConnection),
        (.serverCertificateHasBadDate, .secureConnection),
        (.clientCertificateRequired, .secureConnection),
        (.cancelled, .cancelled),
        (.networkConnectionLost, .connectionLost(receivedText: false)),
        (.badServerResponse, .malformedResponse),
    ])
    func urlErrors(_ code: URLError.Code, _ expected: EngineError) {
        #expect(EngineError(urlError: URLError(code), headersReceived: false, receivedText: false) == expected)
    }

    @Test func aTimeoutOnceTheAnswerStartedIsAnIdleTimeout() {
        #expect(EngineError(urlError: URLError(.timedOut), headersReceived: true, receivedText: true) == .timedOut(.idle))
        #expect(EngineError(urlError: URLError(.networkConnectionLost), headersReceived: true, receivedText: true) == .connectionLost(receivedText: true))
    }

    @Test func normalizingKeepsWhatItCanAndMapsTheRest() {
        let failure = EngineFailure(.overloaded, provider: .anthropic, requestID: "req_9", httpStatus: 529)
        #expect(EngineFailure(normalizing: failure) == failure)
        #expect(EngineFailure(normalizing: EngineError.billing, provider: .openai) == EngineFailure(.billing, provider: .openai))
        #expect(EngineFailure(normalizing: CancellationError()).error == .cancelled)
        #expect(EngineFailure(normalizing: URLError(.notConnectedToInternet)).error == .offline)
    }

    @Test func anHTTPErrorEndToEndCarriesStatusAndRequestID() async throws {
        let server = StubServer()
        server.enqueueJSON(status: 401, body: try Fixture.data("anthropic/error_401.json"), headers: ["request-id": "req_e2e"])
        let outcome = await collect(makeAnthropic(server).stream(sampleRequest(), key: testKey))
        #expect(outcome.failure == EngineFailure(.invalidKey(.anthropic), provider: .anthropic, requestID: "req_e2e", httpStatus: 401))
        #expect(server.requests.count == 1)
    }

    @Test func aTransportErrorEndToEndIsMapped() async {
        let server = StubServer()
        server.enqueue([.fail(.notConnectedToInternet)])
        let outcome = await collect(makeOpenAI(server).stream(sampleRequest(model: "gpt-6.2-sol"), key: testOpenAIKey))
        #expect(outcome.failure?.error == .offline)
        #expect(server.requests.count == 1)
    }
}
