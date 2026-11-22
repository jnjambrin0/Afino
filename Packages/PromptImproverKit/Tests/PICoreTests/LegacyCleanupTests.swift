import Foundation
import Testing
@testable import PICore

struct LegacyCleanupTests {
    private let root = FileManager.default.temporaryDirectory
        .appending(path: "AfinoLegacyTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var locations: LegacyCleanup.Locations {
        .init(
            legacySupportDirectory: root.appending(path: "Support/PromptImprover", directoryHint: .isDirectory),
            legacyCachesDirectory: root.appending(path: "Caches/PromptImprover", directoryHint: .isDirectory),
            legacyTemporaryDirectory: root.appending(path: "Temp/PromptImprover", directoryHint: .isDirectory),
            keepDirectory: root.appending(path: "Support/com.jnjambrin0.PromptImprover/Legacy-0.x", directoryHint: .isDirectory)
        )
    }

    /// Stands in for the Trash: a folder inside the test's own directory.
    private var trashDirectory: URL { root.appending(path: "Trash", directoryHint: .isDirectory) }

    private func cleanup() -> LegacyCleanup {
        let trashDirectory = trashDirectory
        return LegacyCleanup(locations: locations, removePreference: { _ in }) { url in
            try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trashDirectory.appending(path: url.lastPathComponent))
        }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test
    func nothingToDoWithoutLegacyData() throws {
        #expect(try cleanup().run() == .nothingToDo)
    }

    @Test
    func generatedDataGoesToTheTrashAndCachesAreRemoved() throws {
        let locations = locations
        try write("{}", to: locations.legacySupportDirectory.appending(path: "settings.json"))
        try write("{}", to: locations.legacySupportDirectory.appending(path: "model-mapping.json"))
        try FileManager.default.createDirectory(
            at: locations.legacySupportDirectory.appending(path: "guides/user/forks"), withIntermediateDirectories: true)
        try write("{}", to: locations.legacyCachesDirectory.appending(path: "cli-discovery-cache.json"))
        try write("x", to: locations.legacyTemporaryDirectory.appending(path: "run-1/INPUT_PROMPT.txt"))

        #expect(try cleanup().run() == .trashedGeneratedData)
        #expect(!exists(locations.legacySupportDirectory))
        #expect(!exists(locations.legacyCachesDirectory))
        #expect(!exists(locations.legacyTemporaryDirectory))
        #expect(exists(trashDirectory.appending(path: "PromptImprover/settings.json")))
        #expect(try cleanup().run() == .nothingToDo)
    }

    @Test
    func userWrittenGuidesAreKeptNeverDeleted() throws {
        let locations = locations
        try write("# My guide", to: locations.legacySupportDirectory.appending(path: "guides/user/guide-1.md"))
        try write("# Edited built-in", to: locations.legacySupportDirectory.appending(path: "guides/user/forks/claude.md"))
        try write("{}", to: locations.legacySupportDirectory.appending(path: "settings.json"))

        #expect(try cleanup().run() == .keptUserGuides(at: locations.keepDirectory))
        #expect(!exists(locations.legacySupportDirectory))
        #expect(!exists(trashDirectory))
        let kept = try String(contentsOf: locations.keepDirectory.appending(path: "guides/user/guide-1.md"), encoding: .utf8)
        #expect(kept == "# My guide")
        #expect(exists(locations.keepDirectory.appending(path: "guides/user/forks/claude.md")))
    }

    @Test
    func anExistingKeepFolderIsNotOverwritten() throws {
        let locations = locations
        try write("earlier", to: locations.keepDirectory.appending(path: "note.txt"))
        try write("# My guide", to: locations.legacySupportDirectory.appending(path: "guides/user/guide-1.md"))

        let outcome = try cleanup().run()
        let second = locations.keepDirectory.deletingLastPathComponent().appending(path: "Legacy-0.x (2)", directoryHint: .isDirectory)
        #expect(outcome == .keptUserGuides(at: second))
        #expect(exists(locations.keepDirectory.appending(path: "note.txt")))
        #expect(exists(second.appending(path: "guides/user/guide-1.md")))
    }

    @Test
    func aFailedTrashLeavesTheFolderInPlace() throws {
        struct TrashUnavailable: Error {}
        let locations = locations
        try write("{}", to: locations.legacySupportDirectory.appending(path: "settings.json"))
        let failing = LegacyCleanup(locations: locations, removePreference: { _ in }) { _ in throw TrashUnavailable() }

        #expect(throws: TrashUnavailable.self) { try failing.run() }
        #expect(exists(locations.legacySupportDirectory.appending(path: "settings.json")))
    }
}
