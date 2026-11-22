import Foundation
@testable import PIPrompts

/// A deterministic generator (SplitMix64), so random draft ids are reproducible in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A degenerate generator that always yields the same value, hence the same draft id candidate.
/// The value is one the standard library's rejection sampling accepts (0 would make it loop).
struct ConstantGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 {
        0x5555_5555_5555_5555
    }
}

/// The resources shipped in the module bundle, loaded once per test.
enum Bundled {
    static func resourcesDirectory() throws -> URL {
        try PromptResources.bundledDirectory()
    }

    static func packsDirectory() throws -> URL {
        try resourcesDirectory().appending(path: PromptResources.packsFolderName, directoryHint: .isDirectory)
    }

    static func library() throws -> TargetPackLibrary {
        try TargetPackLibrary.bundled()
    }

    static func composer() throws -> PromptComposer {
        try PromptComposer.bundled()
    }
}

/// A pack built in memory, for tests that do not care about the shipped content.
func makePack(
    id: String = "test",
    promptLabel: String = "Test Model (Vendor)",
    coversModels: String = "Test family",
    sortOrder: Int = 1,
    guidance: String = "Be clear."
) -> TargetPack {
    TargetPack(
        id: id,
        displayName: "Test",
        vendorFamily: "generic",
        promptLabel: promptLabel,
        coversModels: coversModels,
        monogram: "Te",
        sortOrder: sortOrder,
        packVersion: "2026.11.1",
        reviewedOn: "2026-11-21",
        guidance: guidance
    )
}

/// A scratch folder of pack folders, deleted when the value goes away.
final class TemporaryPacksDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "AfinoPromptsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// A manifest that loads cleanly for a folder named `id`.
    static func validManifest(id: String, sortOrder: Int = 1) -> [String: Any] {
        [
            "schemaVersion": 1,
            "id": id,
            "displayName": "Pack \(id)",
            "vendorFamily": "generic",
            "promptLabel": "Model \(id)",
            "coversModels": "Every \(id) model",
            "monogram": "Pk",
            "sortOrder": sortOrder,
            "sources": [
                ["title": "Docs", "url": "https://example.com/docs", "retrievedOn": "2026-11-21"],
            ],
            "packVersion": "2026.11.1",
            "reviewedOn": "2026-11-21",
        ]
    }

    /// Writes `<folder>/pack.json` (raw text) and, unless nil, `<folder>/guidance.md`.
    func writePack(folder: String, manifestText: String, guidance: String? = "Say what you want.") throws {
        let packFolder = url.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)
        try Data(manifestText.utf8).write(to: packFolder.appending(path: PromptResources.packManifestFileName))
        if let guidance {
            try Data(guidance.utf8).write(to: packFolder.appending(path: PromptResources.packGuidanceFileName))
        }
    }

    func writePack(folder: String, manifest: [String: Any], guidance: String? = "Say what you want.") throws {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try writePack(folder: folder, manifestText: String(decoding: data, as: UTF8.self), guidance: guidance)
    }
}

extension String {
    /// Every match of a regular expression's first capture group.
    func captures(of pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            Range(match.range(at: 1), in: self).map { String(self[$0]) }
        }
    }
}
