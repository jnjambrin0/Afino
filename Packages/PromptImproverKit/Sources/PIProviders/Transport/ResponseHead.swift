import Foundation

/// The parts of an HTTP response head the providers read, copied out of `HTTPURLResponse`.
struct ResponseHead: Sendable, Equatable {
    let status: Int
    /// Header fields by lowercased name.
    let headers: [String: String]
    let requestID: String?

    init(status: Int, headers: [String: String], requestIDHeader: String) {
        self.status = status
        var lowercased: [String: String] = [:]
        for (name, value) in headers { lowercased[name.lowercased()] = value }
        self.headers = lowercased
        requestID = lowercased[requestIDHeader.lowercased()]
    }

    init(_ response: HTTPURLResponse, requestIDHeader: String) {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String else { continue }
            headers[name] = value as? String ?? "\(value)"
        }
        self.init(status: response.statusCode, headers: headers, requestIDHeader: requestIDHeader)
    }

    func value(_ name: String) -> String? { headers[name.lowercased()] }

    var isSuccess: Bool { (200..<300).contains(status) }

    var isEventStream: Bool {
        isSuccess && (value("content-type") ?? "").lowercased().hasPrefix("text/event-stream")
    }

    /// `x-should-retry: true|false`, which overrides the retry table.
    var shouldRetry: Bool? {
        switch value("x-should-retry")?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// `retry-after-ms`, else `Retry-After` in seconds or as an HTTP date.
    func retryAfter(now: Date) -> Duration? {
        RetryAfter.parse(milliseconds: value("retry-after-ms"), header: value("retry-after"), now: now)
    }
}

/// A non-2xx response: its head and up to 64 KB of its body.
struct HTTPErrorResponse: Sendable {
    static let bodyLimit = 64 * 1024
    let head: ResponseHead
    let body: Data
}

/// Turns an error response into the failure of one attempt. Built per request by each provider.
typealias HTTPErrorMapper = @Sendable (HTTPErrorResponse) -> AttemptFailure

/// The wait a provider asks for before a retry.
enum RetryAfter {
    /// `retry-after-ms` when it is a number, else `Retry-After` as seconds or an HTTP date.
    /// Nil when neither says anything usable; a date in the past is a wait of zero.
    static func parse(milliseconds: String?, header: String?, now: Date) -> Duration? {
        if let milliseconds = milliseconds.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
           milliseconds.isFinite, milliseconds >= 0 {
            return .milliseconds(Int64(milliseconds.rounded(.up)))
        }
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = Double(header), seconds.isFinite {
            return .seconds(max(0, seconds))
        }
        guard let date = httpDate(header) else { return nil }
        return .seconds(max(0, date.timeIntervalSince(now)))
    }

    /// IMF-fixdate, RFC 850 and asctime, the three forms HTTP allows.
    static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
