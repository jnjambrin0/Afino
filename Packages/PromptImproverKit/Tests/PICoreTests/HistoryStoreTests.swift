import Foundation
import Testing
@testable import PICore

struct HistoryStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "AfinoHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var fileURL: URL { directory.appending(path: "history.json") }

    private func entry(_ draft: String, at seconds: TimeInterval = 0, id: UUID = UUID()) -> HistoryEntry {
        HistoryEntry(
            id: id, date: Date(timeIntervalSince1970: 1_800_000_000 + seconds), draft: draft, targetID: "claude",
            versions: [.init(text: "Improved \(draft)")], provider: "anthropic", model: "claude-sonnet-5-5"
        )
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test
    func missingFileStartsEmptyAndWritesOwnerOnly() async throws {
        let store = HistoryStore(fileURL: fileURL)
        #expect(await store.load() == .ready)
        #expect(await store.all().isEmpty)

        try await store.record(entry("first", at: 1))
        try await store.record(entry("second", at: 2))
        #expect(await store.all().map(\.draft) == ["second", "first"])
        #expect(await store.recentDrafts(limit: 1) == ["second"])
        #expect(try permissions(fileURL) == 0o600)
        #expect(try permissions(directory) == 0o700)

        let reopened = HistoryStore(fileURL: fileURL)
        #expect(await reopened.load() == .ready)
        #expect(await reopened.all().map(\.draft) == ["second", "first"])
    }

    @Test
    func theFileIsReadOnFirstUseWithoutAnExplicitLoad() async throws {
        let writer = HistoryStore(fileURL: fileURL)
        try await writer.record(entry("kept"))

        let reader = HistoryStore(fileURL: fileURL)
        #expect(await reader.loadState == .notLoaded)
        #expect(await reader.all().map(\.draft) == ["kept"])
        #expect(await reader.loadState == .ready)
    }

    @Test
    func capacityDropsTheOldestEntries() async throws {
        let store = HistoryStore(fileURL: fileURL, capacity: 3)
        await store.load()
        for index in 1...5 {
            try await store.record(entry("draft \(index)", at: TimeInterval(index)))
        }
        #expect(await store.all().map(\.draft) == ["draft 5", "draft 4", "draft 3"])
    }

    @Test
    func recordingTheSameIdReplacesAndMovesToFront() async throws {
        let store = HistoryStore(fileURL: fileURL)
        await store.load()
        let id = UUID()
        try await store.record(entry("refined later", at: 1, id: id))
        try await store.record(entry("other", at: 2))
        var refined = entry("refined later", at: 1, id: id)
        refined.versions.append(.init(text: "Shorter", instruction: "shorter"))
        try await store.record(refined)

        let all = await store.all()
        #expect(all.map(\.draft) == ["refined later", "other"])
        #expect(all.first?.versions.count == 2)
        #expect(all.first?.latestText == "Shorter")
    }

    @Test
    func removeCanBeUndoneInDateOrder() async throws {
        let store = HistoryStore(fileURL: fileURL)
        await store.load()
        let middle = entry("middle", at: 2)
        try await store.record(entry("old", at: 1))
        try await store.record(middle)
        try await store.record(entry("new", at: 3))

        #expect(try await store.remove(id: middle.id) == middle)
        #expect(await store.all().map(\.draft) == ["new", "old"])
        try await store.restore(middle)
        #expect(await store.all().map(\.draft) == ["new", "middle", "old"])
        #expect(try await store.remove(id: UUID()) == nil)
    }

    @Test
    func clearDeletesTheFile() async throws {
        let store = HistoryStore(fileURL: fileURL)
        await store.load()
        try await store.record(entry("gone"))
        try await store.clear()
        #expect(await store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test
    func corruptFileIsSetAsideNotOverwritten() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let state = await store.load()
        guard case .recoveredFromCorruption(let name) = state else {
            Issue.record("Expected recovery, got \(state)")
            return
        }
        #expect(name.hasPrefix("history.corrupt-") && name.hasSuffix(".json"))
        #expect(try Data(contentsOf: directory.appending(path: name)) == garbage)
        #expect(await store.all().isEmpty)

        try await store.record(entry("fresh start"))
        #expect(await store.all().map(\.draft) == ["fresh start"])
    }

    @Test
    func newerSchemaIsLeftUntouchedAndTheStoreGoesInert() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let newer = Data(#"{"schemaVersion": 99, "entries": [{"shape": "from the future"}]}"#.utf8)
        try newer.write(to: fileURL)

        let store = HistoryStore(fileURL: fileURL)
        #expect(await store.load() == .unsupportedNewerVersion(99))
        #expect(await store.all().isEmpty)
        try await store.record(entry("must not be written"))
        try await store.clear()
        #expect(try Data(contentsOf: fileURL) == newer)
    }
}
