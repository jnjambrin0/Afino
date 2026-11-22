import Foundation

/// Every target pack, loaded once and kept in memory, in picker order (`sortOrder`, then `id`).
///
/// The composition root loads it once with `bundled()` and passes it down. A malformed pack is a
/// packaging bug, so loading throws instead of dropping the pack.
public struct TargetPackLibrary: Sendable, Hashable {
    /// Never empty.
    public let packs: [TargetPack]

    /// Builds a library from packs already in memory (tests, previews). Sorts them; throws on an
    /// empty list or a repeated id.
    public init(packs: [TargetPack]) throws(PromptResourceError) {
        guard !packs.isEmpty else { throw .noPacks }
        var seen = Set<String>()
        for pack in packs {
            guard seen.insert(pack.id).inserted else { throw .duplicatePackID(pack.id) }
        }
        self.packs = packs.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
    }

    /// Loads every pack folder under `packsDirectory`. Each visible entry must be a folder named
    /// after its pack id holding exactly `pack.json` and `guidance.md`; anything else throws.
    public init(packsDirectory: URL) throws(PromptResourceError) {
        let folder = PromptResources.packsFolderName
        var loaded: [TargetPack] = []
        for entry in try PromptResources.entries(of: packsDirectory, displayPath: folder) {
            let name = entry.lastPathComponent
            guard PromptResources.isDirectory(entry) else {
                throw .malformedPack(name, reason: "is a file, not a pack folder")
            }
            loaded.append(try Self.loadPack(in: entry, folderName: name))
        }
        try self.init(packs: loaded)
    }

    /// The packs shipped in this module's bundle.
    public static func bundled() throws(PromptResourceError) -> TargetPackLibrary {
        let packs = try PromptResources.bundledDirectory()
            .appending(path: PromptResources.packsFolderName, directoryHint: .isDirectory)
        return try TargetPackLibrary(packsDirectory: packs)
    }

    /// The first pack in picker order (`claude` in the shipped set).
    public var defaultPack: TargetPack {
        packs[0]
    }

    /// The pack with this id.
    ///
    /// Fallback: an unknown or nil id (a setting saved by another version, a pack removed in an
    /// update) resolves to `defaultPack`, so callers always get a usable target.
    public func pack(for id: String?) -> TargetPack {
        id.flatMap(pack(withID:)) ?? defaultPack
    }

    /// The pack with exactly this id, or nil.
    public func pack(withID id: String) -> TargetPack? {
        packs.first { $0.id == id }
    }

    // MARK: - Loading one pack

    /// The `pack.json` schema; `guidance` comes from `guidance.md`.
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let id: String
        let displayName: String
        let vendorFamily: String
        let promptLabel: String
        let coversModels: String
        let monogram: String?
        let symbol: String?
        let sortOrder: Int
        let sources: [TargetPack.Source]
        let packVersion: String
        let reviewedOn: String
    }

    private static let expectedFiles: Set<String> = [
        PromptResources.packManifestFileName,
        PromptResources.packGuidanceFileName,
    ]

    private static let allowedIDCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-")

    /// Reads and validates one pack folder: exactly the two expected files, a manifest that
    /// matches the schema and names its folder, and non-empty guidance.
    static func loadPack(in folder: URL, folderName: String) throws(PromptResourceError) -> TargetPack {
        func malformed(_ reason: String) -> PromptResourceError {
            .malformedPack(folderName, reason: reason)
        }

        let base = "\(PromptResources.packsFolderName)/\(folderName)"
        let files = Set(try PromptResources.entries(of: folder, displayPath: base).map(\.lastPathComponent))
        if let missing = expectedFiles.subtracting(files).sorted().first {
            throw malformed("missing \(missing)")
        }
        if let unexpected = files.subtracting(expectedFiles).sorted().first {
            throw malformed("unexpected file \(unexpected)")
        }

        let manifestPath = "\(base)/\(PromptResources.packManifestFileName)"
        let manifestText = try PromptResources.readText(
            at: folder.appending(path: PromptResources.packManifestFileName),
            displayPath: manifestPath
        )
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(manifestText.utf8))
        } catch {
            throw malformed("\(PromptResources.packManifestFileName) does not match the schema: \(error)")
        }

        guard manifest.schemaVersion == TargetPack.supportedSchemaVersion else {
            throw malformed("unsupported schemaVersion \(manifest.schemaVersion)")
        }
        guard !manifest.id.isEmpty, manifest.id.allSatisfy(allowedIDCharacters.contains) else {
            throw malformed("id '\(manifest.id)' must be lowercase letters, digits and hyphens")
        }
        guard manifest.id == folderName else {
            throw malformed("id '\(manifest.id)' does not match its folder name")
        }
        let requiredText = [
            ("displayName", manifest.displayName),
            ("vendorFamily", manifest.vendorFamily),
            ("promptLabel", manifest.promptLabel),
            ("coversModels", manifest.coversModels),
            ("packVersion", manifest.packVersion),
        ]
        if let (field, _) = requiredText.first(where: { TextNormalization.isBlank($0.1) }) {
            throw malformed("\(field) is empty")
        }
        let hasMonogram = !TextNormalization.isBlank(manifest.monogram ?? "")
        let hasSymbol = !TextNormalization.isBlank(manifest.symbol ?? "")
        guard hasMonogram != hasSymbol else {
            throw malformed("exactly one of monogram and symbol must be set")
        }
        guard TargetPack.parseDay(manifest.reviewedOn) != nil else {
            throw malformed("reviewedOn '\(manifest.reviewedOn)' is not a yyyy-MM-dd day")
        }
        for source in manifest.sources {
            guard source.url.scheme == "https" else {
                throw malformed("source '\(source.title)' needs an https URL")
            }
            guard TargetPack.parseDay(source.retrievedOn) != nil else {
                throw malformed("source '\(source.title)' has an invalid retrievedOn")
            }
        }

        let guidance = try PromptResources.readText(
            at: folder.appending(path: PromptResources.packGuidanceFileName),
            displayPath: "\(base)/\(PromptResources.packGuidanceFileName)"
        )

        return TargetPack(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            displayName: manifest.displayName,
            vendorFamily: manifest.vendorFamily,
            promptLabel: manifest.promptLabel,
            coversModels: manifest.coversModels,
            monogram: hasMonogram ? manifest.monogram : nil,
            symbol: hasSymbol ? manifest.symbol : nil,
            sortOrder: manifest.sortOrder,
            sources: manifest.sources,
            packVersion: manifest.packVersion,
            reviewedOn: manifest.reviewedOn,
            guidance: guidance
        )
    }
}
