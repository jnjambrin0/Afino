import Foundation
@testable import PIApp
import PICore
import PIDesign
import PIPrompts
import Testing

/// History rows: the draft's first line, the result's preview, relative time, filtering, ↑/↓.
struct HistoryRowFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let english = Locale(identifier: "en_US")

    private func entry(draft: String, result: String, target: String = "claude", ago: TimeInterval = 3_600) -> HistoryEntry {
        HistoryEntry(
            date: now.addingTimeInterval(-ago), draft: draft, targetID: target,
            versions: [.init(text: "first"), .init(text: result, instruction: "Shorter")],
            provider: "anthropic", model: "claude-sonnet-5-5")
    }

    // MARK: Lines

    @Test func theTitleIsTheFirstLineWithText() {
        #expect(HistoryRowFormatter.firstLine(of: "\n\n  write a haiku  \nabout latency", limit: 100) == "write a haiku")
    }

    @Test func whitespaceRunsCollapse() {
        #expect(HistoryRowFormatter.firstLine(of: "two\t\tspaces   here", limit: 100) == "two spaces here")
    }

    @Test func markdownMarksAtTheStartAreDropped() {
        #expect(HistoryRowFormatter.firstLine(of: "## Role\nYou are…", limit: 100) == "Role")
        #expect(HistoryRowFormatter.firstLine(of: "> quoted", limit: 100) == "quoted")
        #expect(HistoryRowFormatter.firstLine(of: "- a bullet", limit: 100) == "a bullet")
    }

    @Test func longLinesAreCutWithAnEllipsis() {
        let line = HistoryRowFormatter.firstLine(of: String(repeating: "word ", count: 50), limit: 20)
        #expect(line.hasSuffix("…"))
        #expect(line.count <= 21)
        #expect(!line.contains("  "))
    }

    @Test func anEmptyTextGivesAnEmptyLine() {
        #expect(HistoryRowFormatter.firstLine(of: " \n\t\n", limit: 10).isEmpty)
    }

    // MARK: Time

    @Test func underAMinuteIsNowAndTheFutureToo() {
        #expect(HistoryRowFormatter.relativeTime(from: now.addingTimeInterval(-59), now: now, locale: english) == nil)
        #expect(HistoryRowFormatter.relativeTime(from: now.addingTimeInterval(120), now: now, locale: english) == nil)
    }

    @Test func olderEntriesShowOneCompactUnit() throws {
        let minutes = try #require(HistoryRowFormatter.relativeTime(from: now.addingTimeInterval(-5 * 60), now: now, locale: english))
        let hours = try #require(HistoryRowFormatter.relativeTime(from: now.addingTimeInterval(-2 * 3_600), now: now, locale: english))
        let days = try #require(HistoryRowFormatter.relativeTime(from: now.addingTimeInterval(-3 * 86_400), now: now, locale: english))
        #expect(minutes.hasPrefix("5"))
        #expect(hours.hasPrefix("2"))
        #expect(days.hasPrefix("3"))
        #expect(minutes != hours && hours != days)
        #expect(!minutes.contains(","))
    }

    // MARK: Rows

    @Test func aRowShowsTheDraftTheLatestVersionAndWhoItWasFor() throws {
        let library = try TargetPackLibrary.bundled()
        let row = HistoryRowFormatter.row(
            for: entry(draft: "write a prompt\nfor a game", result: "# You are a game developer\nBuild…"),
            library: library, now: now, locale: english)
        #expect(row.title == "write a prompt")
        #expect(row.preview == "You are a game developer")
        #expect(row.time?.hasPrefix("1") == true)
        #expect(row.monogram == .letters("Cl"))
    }

    @Test func theGenericTargetIsASymbolAndAnUnknownOneFallsBack() throws {
        let library = try TargetPackLibrary.bundled()
        #expect(HistoryRowFormatter.row(for: entry(draft: "a", result: "b", target: "generic"), library: library, now: now).monogram == .symbol("circle.dotted"))
        #expect(HistoryRowFormatter.row(for: entry(draft: "a", result: "b", target: "gone"), library: library, now: now).monogram == .letters("Cl"))
    }

    // MARK: Filter and selection

    @Test func theFilterMatchesEveryWordInTheDraftOrTheResult() {
        let entries = [
            entry(draft: "Résumé helper", result: "You are a career coach"),
            entry(draft: "snake game", result: "Build a canvas game"),
            entry(draft: "SQL review", result: "Review this query for performance"),
        ]
        #expect(HistoryRowFormatter.filter(entries, query: "").count == 3)
        #expect(HistoryRowFormatter.filter(entries, query: "resume").map(\.draft) == ["Résumé helper"])
        #expect(HistoryRowFormatter.filter(entries, query: "GAME canvas").map(\.draft) == ["snake game"])
        #expect(HistoryRowFormatter.filter(entries, query: "performance").map(\.draft) == ["SQL review"])
        #expect(HistoryRowFormatter.filter(entries, query: "game sql").isEmpty)
    }

    @Test func arrowsWrapRound() {
        #expect(HistoryRowFormatter.step(from: nil, count: 3, forward: true) == 0)
        #expect(HistoryRowFormatter.step(from: nil, count: 3, forward: false) == 2)
        #expect(HistoryRowFormatter.step(from: 2, count: 3, forward: true) == 0)
        #expect(HistoryRowFormatter.step(from: 0, count: 3, forward: false) == 2)
        #expect(HistoryRowFormatter.step(from: 1, count: 3, forward: true) == 2)
        #expect(HistoryRowFormatter.step(from: 0, count: 0, forward: true) == nil)
    }
}
