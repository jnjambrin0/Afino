import Foundation
import os
import PIFoundation

/// Clears what versions 0.x left on disk. They shipped under the name PromptImprover, which is
/// why the folders below carry it. 0.x drove command-line tools and kept guides, engine settings
/// and a capability cache; none of it means anything to 1.x.
///
/// Nothing the user wrote is ever deleted. If 0.x holds guides the user imported or edited, the
/// whole folder is moved next to the new data as `Legacy-0.x`; otherwise the folder, which then
/// only contains generated files, goes to the Trash.
public nonisolated struct LegacyCleanup: Sendable {
    /// What a run of the cleanup did.
    public enum Outcome: Sendable, Equatable {
        /// There was no 0.x data.
        case nothingToDo
        /// Generated files only; the old folder is in the Trash.
        case trashedGeneratedData
        /// The user's guides were kept at this location.
        case keptUserGuides(at: URL)
    }

    /// Where 0.x kept things, and where 1.x keeps a copy of anything worth keeping.
    public struct Locations: Sendable {
        /// `Application Support/PromptImprover`: 0.x's settings and guides, including any the
        /// user imported or edited.
        public var legacySupportDirectory: URL
        /// `Caches/PromptImprover`: regenerable.
        public var legacyCachesDirectory: URL
        /// The 0.x scratch folder in the temporary directory: regenerable.
        public var legacyTemporaryDirectory: URL
        /// Where a support folder holding the user's guides is moved: `Legacy-0.x` in Afino's
        /// own Application Support folder.
        public var keepDirectory: URL

        public init(
            legacySupportDirectory: URL = URL.applicationSupportDirectory.appending(path: "PromptImprover", directoryHint: .isDirectory),
            legacyCachesDirectory: URL = URL.cachesDirectory.appending(path: "PromptImprover", directoryHint: .isDirectory),
            legacyTemporaryDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "PromptImprover", directoryHint: .isDirectory),
            keepDirectory: URL = AppIdentity.applicationSupportDirectory.appending(path: "Legacy-0.x", directoryHint: .isDirectory)
        ) {
            self.legacySupportDirectory = legacySupportDirectory
            self.legacyCachesDirectory = legacyCachesDirectory
            self.legacyTemporaryDirectory = legacyTemporaryDirectory
            self.keepDirectory = keepDirectory
        }
    }

    /// Preference keys only 0.x wrote.
    static let legacyDefaultsKeys = ["settings.guides.workspace.mode", "updates.movePrompt.lastHandledVersion"]

    private let locations: Locations
    /// Removes one preference key. Injected so tests do not touch the real preferences.
    private let removePreference: @Sendable (String) -> Void
    /// Moves a folder out of the way for good. Injected so tests do not fill the Trash.
    private let trash: @Sendable (URL) throws -> Void

    public init(
        locations: Locations = Locations(),
        removePreference: @escaping @Sendable (String) -> Void = { UserDefaults.standard.removeObject(forKey: $0) },
        trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.locations = locations
        self.removePreference = removePreference
        self.trash = trash
    }

    /// Runs the cleanup. Idempotent: a second run finds nothing to do. Throws only when the old
    /// folder could neither be kept nor trashed, in which case it is left exactly as it was and
    /// the caller should try again on a later launch.
    @discardableResult
    public func run() throws -> Outcome {
        let fileManager = FileManager.default
        // Regenerable, so failures here are not worth reporting.
        try? fileManager.removeItem(at: locations.legacyCachesDirectory)
        try? fileManager.removeItem(at: locations.legacyTemporaryDirectory)
        for key in Self.legacyDefaultsKeys {
            removePreference(key)
        }

        let support = locations.legacySupportDirectory
        guard fileManager.fileExists(atPath: support.path(percentEncoded: false)) else { return .nothingToDo }

        if hasUserGuides(in: support) {
            let destination = uniqueDestination(locations.keepDirectory)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: support, to: destination)
            Log.logger(.store).notice("Kept 0.x guides the user wrote")
            return .keptUserGuides(at: destination)
        }
        try trash(support)
        return .trashedGeneratedData
    }

    /// 0.x stored imported guides in `guides/user` and edited built-in ones in `guides/user/forks`.
    private func hasUserGuides(in support: URL) -> Bool {
        let userGuides = support.appending(path: "guides/user", directoryHint: .isDirectory)
        guard let contents = FileManager.default.enumerator(
            at: userGuides, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in contents where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return true
        }
        return false
    }

    /// `preferred`, or `preferred (2)`, `(3)`… when a folder of that name already exists.
    private func uniqueDestination(_ preferred: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: preferred.path(percentEncoded: false)) else { return preferred }
        var index = 2
        while true {
            let candidate = preferred.deletingLastPathComponent()
                .appending(path: "\(preferred.lastPathComponent) (\(index))", directoryHint: .isDirectory)
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
            index += 1
        }
    }
}
