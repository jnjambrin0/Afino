import Foundation
import Testing
@testable import PIProviders

struct SSEParserTests {
    private func parse(_ text: String) throws -> [SSEEvent] {
        var parser = SSEParser()
        var events = try parser.feed(Data(text.utf8))
        if let last = parser.finish() { events.append(last) }
        return events
    }

    @Test func namedEventJoinsItsDataLines() throws {
        let events = try parse("event: delta\ndata: first\ndata: second\n\n")
        #expect(events == [SSEEvent(name: "delta", data: "first\nsecond")])
    }

    @Test func unnamedEventIsAMessage() throws {
        #expect(try parse("data: {}\n\n") == [SSEEvent(name: "message", data: "{}")])
    }

    @Test func commentsIdsRetriesAndUnknownFieldsAreIgnored() throws {
        let events = try parse(": keep-alive\nid: 7\nretry: 1000\nfoo: bar\ndata: x\n\n: trailing comment\n\n")
        #expect(events == [SSEEvent(name: "message", data: "x")])
    }

    @Test func onlyOneSpaceAfterTheColonIsDropped() throws {
        #expect(try parse("data:x\n\n") == [SSEEvent(name: "message", data: "x")])
        #expect(try parse("data:  x\n\n") == [SSEEvent(name: "message", data: " x")])
    }

    @Test func aFieldWithoutAColonHasAnEmptyValue() throws {
        #expect(try parse("data\n\n") == [SSEEvent(name: "message", data: "")])
    }

    @Test func blankLinesWithoutDataDispatchNothing() throws {
        #expect(try parse("\n\n\nevent: ping\n\n\n").isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func everyLineEndingWorks(_ newline: String) throws {
        let text = ["event: a", "data: 1", "", "data: 2", "data: 3", "", ""].joined(separator: newline)
        #expect(try parse(text) == [SSEEvent(name: "a", data: "1"), SSEEvent(name: "message", data: "2\n3")])
    }

    @Test func aCRLFSplitAcrossPiecesEndsOneLine() throws {
        var parser = SSEParser()
        #expect(try parser.feed(Data("data: a\r".utf8)).isEmpty)
        #expect(try parser.feed(Data("\n".utf8)).isEmpty)
        #expect(try parser.feed(Data("\r".utf8)) == [SSEEvent(name: "message", data: "a")])
        #expect(try parser.feed(Data("\n".utf8)).isEmpty)
    }

    @Test func aMultiByteCharacterSplitAtAnyByteSurvives() throws {
        let bytes = Array("data: café 東京 🌧️ — ok\n\n".utf8)
        for split in 1..<bytes.count {
            var parser = SSEParser()
            let events = try parser.feed(bytes[..<split]) + parser.feed(bytes[split...])
            #expect(events == [SSEEvent(name: "message", data: "café 東京 🌧️ — ok")], "split at \(split)")
        }
    }

    @Test func aLeadingByteOrderMarkIsDropped() throws {
        let events = try parse("\u{FEFF}data: x\n\n")
        #expect(events == [SSEEvent(name: "message", data: "x")])
    }

    @Test func theEndDispatchesACompleteLastLineButNotAHalfOne() throws {
        #expect(try parse("data: done\n") == [SSEEvent(name: "message", data: "done")])
        #expect(try parse("data: done\ndata: {\"type\":\"cont").isEmpty)
    }

    @Test func anOversizedEventIsAnError() {
        var parser = SSEParser()
        let line = Data("data: ".utf8) + Data(repeating: UInt8(ascii: "a"), count: SSEParser.maximumEventBytes)
        #expect(throws: SSEParser.ParseError.eventTooLarge) { try parser.feed(line) }
    }

    static let fixtures = [
        "anthropic/ok_text.sse", "anthropic/max_tokens.sse", "anthropic/refusal.sse",
        "anthropic/fallback_midstream.sse", "anthropic/error_overloaded_midstream.sse", "anthropic/cut_off.sse",
        "openai/ok_text.sse", "openai/incomplete_max_output_tokens.sse", "openai/refusal.sse",
        "openai/failed.sse", "openai/error_event.sse",
    ]

    @Test(arguments: fixtures, Replay.all)
    func everyFixtureParsesTheSameHoweverItIsCut(_ path: String, _ replay: Replay) throws {
        let data = try Fixture.data(path)
        var reference = SSEParser()
        var expected = try reference.feed(data)
        if let last = reference.finish() { expected.append(last) }
        #expect(!expected.isEmpty)

        var parser = SSEParser()
        var events: [SSEEvent] = []
        for chunk in Fixture.chunks(replay.prepare(data), size: replay.chunkSize) {
            events += try parser.feed(chunk)
        }
        if let last = parser.finish() { events.append(last) }
        #expect(events == expected)
    }
}
