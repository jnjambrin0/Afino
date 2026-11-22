import Foundation
import Testing
@testable import PIPrompts

struct BundledPackTests {
    static let shippedIDs = ["claude", "gpt", "gemini", "generic"]

    @Test func loadsTheFourShippedPacksInPickerOrder() throws {
        let library = try Bundled.library()

        #expect(library.packs.map(\.id) == Self.shippedIDs)
        #expect(library.packs.map(\.sortOrder) == library.packs.map(\.sortOrder).sorted())
        #expect(Set(library.packs.map(\.sortOrder)).count == library.packs.count, "sortOrder values must be unique")
        #expect(library.defaultPack.id == "claude")
    }

    @Test(arguments: shippedIDs)
    func everyPackResolvesWithNonEmptyGuidance(id: String) throws {
        let library = try Bundled.library()
        let pack = try #require(library.pack(withID: id))

        #expect(library.pack(for: id) == pack)
        #expect(pack.schemaVersion == TargetPack.supportedSchemaVersion)
        #expect(!pack.guidance.isEmpty)
        #expect(pack.guidance == pack.guidance.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!pack.guidance.contains("\r"))
        #expect(!pack.displayName.isEmpty && !pack.promptLabel.isEmpty && !pack.coversModels.isEmpty)
    }

    @Test func unknownOrMissingIDsFallBackToTheFirstPack() throws {
        let library = try Bundled.library()

        #expect(library.pack(for: "llama") == library.packs[0])
        #expect(library.pack(for: "") == library.packs[0])
        #expect(library.pack(for: nil) == library.packs[0])
        #expect(library.pack(withID: "llama") == nil)
    }

    @Test(arguments: shippedIDs)
    func guidanceStaysWithinSevenHundredWords(id: String) throws {
        let pack = try #require(try Bundled.library().pack(withID: id))
        let words = pack.guidance.split(whereSeparator: \.isWhitespace).count

        #expect(words > 0)
        #expect(words <= 700, "\(id) guidance has \(words) words; the cap is 700")
    }

    @Test(arguments: shippedIDs)
    func reviewedOnIsARecentDay(id: String) throws {
        let pack = try #require(try Bundled.library().pack(withID: id))
        let reviewed = try #require(pack.reviewDate, "reviewedOn '\(pack.reviewedOn)' is not yyyy-MM-dd")

        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: reviewed, to: .now).day ?? 0
        if days > 180 {
            withKnownIssue("Target pack guidance is due for review") {
                Issue.record("Pack '\(id)' was last reviewed \(days) days ago (\(pack.reviewedOn)); re-check it against its sources.")
            }
        }
    }

    @Test func badgesComeFromMonogramOrSymbol() throws {
        let library = try Bundled.library()

        #expect(library.pack(for: "claude").badge == .monogram("Cl"))
        #expect(library.pack(for: "gpt").badge == .monogram("Gp"))
        #expect(library.pack(for: "gemini").badge == .monogram("Ge"))
        #expect(library.pack(for: "generic").badge == .symbol("circle.dotted"))
    }

    /// Checks the shipped folder directly, independently of the loader.
    @Test func noOrphanResources() throws {
        let fileManager = FileManager.default
        let resources = try Bundled.resourcesDirectory()
        let topLevel = try fileManager.contentsOfDirectory(atPath: resources.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
        #expect(Set(topLevel) == ["core.txt", "Packs"])

        let packs = try Bundled.packsDirectory()
        let folders = try fileManager.contentsOfDirectory(atPath: packs.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
            .sorted()
        var ids: [String] = []
        for folder in folders {
            let packFolder = packs.appending(path: folder, directoryHint: .isDirectory)
            let files = try fileManager.contentsOfDirectory(atPath: packFolder.path(percentEncoded: false))
                .filter { !$0.hasPrefix(".") }
            #expect(Set(files) == ["pack.json", "guidance.md"], "Packs/\(folder) holds \(files.sorted())")

            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: packFolder.appending(path: "pack.json")))
            let id = try #require((json as? [String: Any])?["id"] as? String)
            #expect(id == folder)
            ids.append(id)
        }

        #expect(Set(ids).count == ids.count, "pack ids must be unique")
        #expect(Set(ids) == Set(try Bundled.library().packs.map(\.id)))
    }
}

struct TargetPackLoadingTests {
    @Test func loadsAValidFolderAndTrimsGuidance() throws {
        let directory = try TemporaryPacksDirectory()
        try directory.writePack(folder: "beta", manifest: TemporaryPacksDirectory.validManifest(id: "beta", sortOrder: 2))
        try directory.writePack(
            folder: "alpha",
            manifest: TemporaryPacksDirectory.validManifest(id: "alpha", sortOrder: 5),
            guidance: "\r\n  First line.\r\nSecond line.\n\n"
        )

        let library = try TargetPackLibrary(packsDirectory: directory.url)

        #expect(library.packs.map(\.id) == ["beta", "alpha"])
        #expect(library.pack(for: "alpha").guidance == "First line.\nSecond line.")
        #expect(library.pack(for: "alpha").sources.first?.url == URL(string: "https://example.com/docs"))
    }

    enum Malformation: String, CaseIterable, Sendable {
        case invalidJSON
        case missingField
        case wrongFieldType
        case unsupportedSchemaVersion
        case idDoesNotMatchFolder
        case uppercaseID
        case blankPromptLabel
        case bothMonogramAndSymbol
        case neitherMonogramNorSymbol
        case impossibleReviewDay
        case reviewDayInWrongFormat
        case insecureSourceURL
        case missingGuidance
        case blankGuidance
        case strayFileInPackFolder
    }

    @Test(arguments: Malformation.allCases)
    func malformedPacksThrowInsteadOfBeingDropped(_ malformation: Malformation) throws {
        let directory = try TemporaryPacksDirectory()
        try directory.writePack(folder: "good", manifest: TemporaryPacksDirectory.validManifest(id: "good"))

        var manifest = TemporaryPacksDirectory.validManifest(id: "bad", sortOrder: 2)
        var guidance: String? = "Say what you want."
        var folder = "bad"
        switch malformation {
        case .invalidJSON:
            try directory.writePack(folder: folder, manifestText: "{ \"id\": \"bad\", ")
        case .missingField:
            manifest["promptLabel"] = nil
        case .wrongFieldType:
            manifest["sortOrder"] = "first"
        case .unsupportedSchemaVersion:
            manifest["schemaVersion"] = 2
        case .idDoesNotMatchFolder:
            manifest["id"] = "other"
        case .uppercaseID:
            folder = "Bad"
            manifest["id"] = "Bad"
        case .blankPromptLabel:
            manifest["promptLabel"] = "  "
        case .bothMonogramAndSymbol:
            manifest["symbol"] = "circle"
        case .neitherMonogramNorSymbol:
            manifest["monogram"] = nil
        case .impossibleReviewDay:
            manifest["reviewedOn"] = "2026-02-30"
        case .reviewDayInWrongFormat:
            manifest["reviewedOn"] = "21/11/2026"
        case .insecureSourceURL:
            manifest["sources"] = [["title": "Docs", "url": "http://example.com", "retrievedOn": "2026-11-21"]]
        case .missingGuidance:
            guidance = nil
        case .blankGuidance:
            guidance = " \n\n "
        case .strayFileInPackFolder:
            try Data("notes".utf8).write(to: directory.url.appending(path: "good/notes.txt"))
        }
        if malformation != .invalidJSON {
            try directory.writePack(folder: folder, manifest: manifest, guidance: guidance)
        }

        #expect(throws: PromptResourceError.self) {
            try TargetPackLibrary(packsDirectory: directory.url)
        }
    }

    @Test func aStrayFileNextToThePackFoldersThrows() throws {
        let directory = try TemporaryPacksDirectory()
        try directory.writePack(folder: "good", manifest: TemporaryPacksDirectory.validManifest(id: "good"))
        try Data("x".utf8).write(to: directory.url.appending(path: "README.md"))

        #expect(throws: PromptResourceError.malformedPack("README.md", reason: "is a file, not a pack folder")) {
            try TargetPackLibrary(packsDirectory: directory.url)
        }
    }

    @Test func missingGuidanceNamesTheFile() throws {
        let directory = try TemporaryPacksDirectory()
        try directory.writePack(folder: "solo", manifest: TemporaryPacksDirectory.validManifest(id: "solo"), guidance: nil)

        #expect(throws: PromptResourceError.malformedPack("solo", reason: "missing guidance.md")) {
            try TargetPackLibrary(packsDirectory: directory.url)
        }
    }

    @Test func anEmptyOrMissingFolderThrows() throws {
        let directory = try TemporaryPacksDirectory()
        #expect(throws: PromptResourceError.noPacks) {
            try TargetPackLibrary(packsDirectory: directory.url)
        }
        #expect(throws: PromptResourceError.missingResource("Packs")) {
            try TargetPackLibrary(packsDirectory: directory.url.appending(path: "nowhere"))
        }
    }

    @Test func duplicateIDsThrow() {
        #expect(throws: PromptResourceError.duplicatePackID("same")) {
            try TargetPackLibrary(packs: [makePack(id: "same"), makePack(id: "same", sortOrder: 2)])
        }
        #expect(throws: PromptResourceError.noPacks) {
            try TargetPackLibrary(packs: [])
        }
    }

    @Test func equalSortOrdersAreBrokenByID() throws {
        let library = try TargetPackLibrary(packs: [makePack(id: "b"), makePack(id: "a")])
        #expect(library.packs.map(\.id) == ["a", "b"])
    }

    @Test func reviewDayParsingIsStrict() {
        #expect(TargetPack.parseDay("2026-11-21") != nil)
        #expect(TargetPack.parseDay("2024-02-29") != nil)
        #expect(TargetPack.parseDay("2026-02-29") == nil)
        #expect(TargetPack.parseDay("2026-13-01") == nil)
        #expect(TargetPack.parseDay("2026-1-5") == nil)
        #expect(TargetPack.parseDay("") == nil)
    }

    @Test func packsRoundTripThroughCodable() throws {
        let pack = try Bundled.library().pack(for: "generic")
        let decoded = try JSONDecoder().decode(TargetPack.self, from: JSONEncoder().encode(pack))
        #expect(decoded == pack)
    }
}
