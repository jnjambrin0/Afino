import Foundation
import os
import PIFoundation

/// The last improvements, kept in one JSON file that only this user can read.
///
/// The file is never overwritten unless it was read cleanly first, so a history is never lost to
/// a failed decode: a corrupt file is set aside under a new name, and a file written by a newer
/// version of the app is left alone, the history being unavailable until the app is updated.
public actor HistoryStore {
    /// The `schemaVersion` this build writes, and the newest it reads.
    public static let currentSchemaVersion = 1
    /// How many entries are kept unless the caller says otherwise.
    public static let defaultCapacity = 50

    /// What happened when the file was read.
    public enum LoadState: Sendable, Equatable {
        /// The file has not been read yet.
        case notLoaded
        /// Read successfully, or there was no file yet.
        case ready
        /// The file could not be decoded. It was renamed to `setAsideAs` and a fresh history started.
        case recoveredFromCorruption(setAsideAs: String)
        /// The file comes from a newer version of the app: nothing is shown and nothing is written.
        case unsupportedNewerVersion(Int)
        /// The file is unreadable and could not be set aside: nothing is shown and nothing is
        /// written, so whatever it holds is left exactly as it is.
        case unavailable
    }

    private nonisolated struct Envelope: Codable {
        var schemaVersion: Int
        var entries: [HistoryEntry]
    }

    private nonisolated struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    private let fileURL: URL
    private let capacity: Int
    private let jsonStore: AtomicJSONStore
    private let now: @Sendable () -> Date
    private var entries: [HistoryEntry] = []
    /// What came of reading the file; `notLoaded` until something uses the store.
    public private(set) var loadState: LoadState = .notLoaded

    /// - Parameters:
    ///   - fileURL: Where the history lives; its folder is created and restricted to the user.
    ///   - capacity: How many entries are kept; the oldest are dropped first.
    ///   - now: The clock that names a corrupt file when it is set aside.
    public init(
        fileURL: URL = AppIdentity.applicationSupportDirectory.appending(path: "history.json"),
        capacity: Int = HistoryStore.defaultCapacity,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.capacity = max(1, capacity)
        self.jsonStore = AtomicJSONStore()
        self.now = now
    }

    /// Reads the file once. Safe to call again: later calls return the state already reached.
    /// Every other method calls it first, so there is no order the caller can get wrong.
    @discardableResult
    public func load() -> LoadState {
        guard loadState == .notLoaded else { return loadState }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            loadState = .ready
            return loadState
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let version = try Self.decoder.decode(VersionProbe.self, from: data).schemaVersion
            guard version <= Self.currentSchemaVersion else {
                loadState = .unsupportedNewerVersion(version)
                Log.logger(.store).notice("History file has schema \(version, privacy: .public); leaving it untouched")
                return loadState
            }
            entries = try Self.decoder.decode(Envelope.self, from: data).entries
            loadState = .ready
        } catch {
            loadState = setAsideCorruptFile()
        }
        return loadState
    }

    /// Newest first. Empty unless the history is usable.
    public func all() -> [HistoryEntry] {
        isUsable ? entries : []
    }

    /// The drafts of the most recent entries, newest first, for recalling them with ↑ in an
    /// empty input.
    public func recentDrafts(limit: Int = HistoryStore.defaultCapacity) -> [String] {
        Array(all().prefix(limit).map(\.draft))
    }

    /// Adds an entry, or replaces the one with the same id (a refinement adds a version to the
    /// run that is already recorded), and moves it to the front.
    public func record(_ entry: HistoryEntry) throws {
        guard isUsable else { return }
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        try persist()
    }

    /// Removes one entry and returns it, so the caller can offer to undo.
    @discardableResult
    public func remove(id: HistoryEntry.ID) throws -> HistoryEntry? {
        guard isUsable, let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = entries.remove(at: index)
        try persist()
        return removed
    }

    /// Puts back an entry removed by mistake, in date order.
    public func restore(_ entry: HistoryEntry) throws {
        guard isUsable, !entries.contains(where: { $0.id == entry.id }) else { return }
        let index = entries.firstIndex { $0.date < entry.date } ?? entries.endIndex
        entries.insert(entry, at: index)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        try persist()
    }

    /// Deletes every entry and the file itself.
    public func clear() throws {
        guard isUsable else { return }
        entries.removeAll()
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private var isUsable: Bool {
        switch load() {
        case .ready, .recoveredFromCorruption: true
        case .notLoaded, .unsupportedNewerVersion, .unavailable: false
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try OwnerOnlyAccess.restrict(directory)
        try jsonStore.encodeAndWrite(
            Envelope(schemaVersion: Self.currentSchemaVersion, entries: entries),
            to: fileURL,
            using: Self.encoder
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: OwnerOnlyAccess.filePermissions)],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
    }

    private func setAsideCorruptFile() -> LoadState {
        let stamp = Self.stampFormatter.string(from: now())
        let name = "history.corrupt-\(stamp).json"
        let destination = fileURL.deletingLastPathComponent().appending(path: name)
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            Log.logger(.store).error("History file was unreadable; set aside as \(name, privacy: .public)")
            entries = []
            return .recoveredFromCorruption(setAsideAs: name)
        } catch {
            // The unreadable file could not even be moved: treat the history as unavailable so
            // nothing is written on top of it.
            Log.logger(.store).error("History file was unreadable and could not be set aside")
            return .unavailable
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
