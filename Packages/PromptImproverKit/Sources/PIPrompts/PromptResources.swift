import Foundation

/// Why the bundled prompt resources (`core.txt` and the target packs) could not be loaded.
///
/// These files ship inside the app, so any of these errors is a packaging bug: loading fails loudly
/// instead of quietly running with a pack missing.
public enum PromptResourceError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A file or folder that must exist is not there (path relative to the resources folder).
    case missingResource(String)
    /// A file exists but cannot be read as non-empty UTF-8 text.
    case unreadableResource(String, reason: String)
    /// A pack folder breaks the pack schema; the first value is the folder name.
    case malformedPack(String, reason: String)
    /// Two packs declare the same id.
    case duplicatePackID(String)
    /// The library would be empty.
    case noPacks

    public var description: String {
        switch self {
        case .missingResource(let path):
            "Missing prompt resource: \(path)"
        case .unreadableResource(let path, let reason):
            "Unreadable prompt resource \(path): \(reason)"
        case .malformedPack(let folder, let reason):
            "Malformed target pack '\(folder)': \(reason)"
        case .duplicatePackID(let id):
            "Two target packs declare the id '\(id)'"
        case .noPacks:
            "No target packs found"
        }
    }
}

/// Where the engine's text resources live and how they are read.
///
/// The manifest declares `.copy("Resources")`, so the whole folder lands in the module bundle as a
/// subfolder named `Resources` (`PromptImproverKit_PIPrompts.bundle/Contents/Resources/Resources/`).
enum PromptResources {
    static let folderName = "Resources"
    static let coreFileName = "core.txt"
    static let packsFolderName = "Packs"
    static let packManifestFileName = "pack.json"
    static let packGuidanceFileName = "guidance.md"

    /// The copied `Resources` folder inside this module's bundle.
    static func bundledDirectory() throws(PromptResourceError) -> URL {
        guard let url = Bundle.module.url(forResource: folderName, withExtension: nil) else {
            throw .missingResource(folderName)
        }
        return url
    }

    /// Reads a UTF-8 text file exactly as stored. `displayPath` names it in errors.
    static func readText(at url: URL, displayPath: String) throws(PromptResourceError) -> String {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw .missingResource(displayPath)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadableResource(displayPath, reason: error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw .unreadableResource(displayPath, reason: "not valid UTF-8")
        }
        guard !text.allSatisfy(\.isWhitespace) else {
            throw .unreadableResource(displayPath, reason: "empty")
        }
        return text
    }

    /// The visible (non-hidden) entries of a folder, sorted by name so loading order never depends
    /// on the file system.
    static func entries(of directory: URL, displayPath: String) throws(PromptResourceError) -> [URL] {
        do {
            return try FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw .missingResource(displayPath)
        }
    }

    /// Whether `url` is a folder; false when it cannot be checked.
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
