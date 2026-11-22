import Foundation

/// One server-sent event: its `event:` name ("message" when unnamed) and its `data:` lines
/// joined by `\n`.
struct SSEEvent: Equatable, Sendable {
    var name: String
    var data: String
}

/// Server-sent events from raw bytes fed in any pieces, following the WHATWG HTML event-stream
/// format: `event:` and `data:` fields, comment lines, `\n`, `\r\n` or `\r` line ends (a `\r\n`
/// split across two pieces included), a UTF-8 BOM at the start, and an event dispatched at a
/// blank line. Lines are decoded only once complete, so a multi-byte character split across
/// pieces is never torn. An event over 4 MB is a protocol error.
struct SSEParser {
    enum ParseError: Error, Equatable {
        case eventTooLarge
    }

    static let maximumEventBytes = 4 * 1024 * 1024

    private var line: [UInt8] = []
    private var name = ""
    private var data: [String] = []
    private var eventBytes = 0
    private var afterCarriageReturn = false
    private var isFirstLine = true

    /// The events completed by `bytes`. The client feeds one byte at a time with `append`; this
    /// is the same loop for callers that hold a whole buffer.
    mutating func feed(_ bytes: some Sequence<UInt8>) throws(ParseError) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in bytes {
            if let event = try append(byte) { events.append(event) }
        }
        return events
    }

    /// One more byte; the event it completes, if any.
    mutating func append(_ byte: UInt8) throws(ParseError) -> SSEEvent? {
        switch byte {
        case 0x0A:
            // The LF of a CRLF pair: the CR already ended the line.
            if afterCarriageReturn {
                afterCarriageReturn = false
                return nil
            }
            return endLine()
        case 0x0D:
            afterCarriageReturn = true
            return endLine()
        default:
            afterCarriageReturn = false
            line.append(byte)
            eventBytes += 1
            if eventBytes > Self.maximumEventBytes { throw .eventTooLarge }
            return nil
        }
    }

    /// The stream ended. An event whose last line was complete is dispatched even without the
    /// closing blank line, which the spec would drop, so a provider's final event is not lost to
    /// a missing newline. A half-received line is discarded.
    mutating func finish() -> SSEEvent? {
        defer { reset() }
        guard line.isEmpty, !data.isEmpty else { return nil }
        return SSEEvent(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
    }

    private mutating func endLine() -> SSEEvent? {
        defer { line.removeAll(keepingCapacity: true) }
        if isFirstLine {
            isFirstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        guard !line.isEmpty else {
            defer { reset() }
            guard !data.isEmpty else { return nil }
            return SSEEvent(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
        }
        let text = String(decoding: line, as: UTF8.self)
        if text.hasPrefix(":") { return nil }
        let field: Substring
        let value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            var rest = text[text.index(after: colon)...]
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
            value = rest
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break // id, retry and unknown fields don't matter here
        }
        return nil
    }

    private mutating func reset() {
        name = ""
        data = []
        eventBytes = 0
    }
}
