import Foundation

/// Writes JSON files atomically: the data lands in a sibling temporary file that then replaces
/// the destination, so a crash mid-write never leaves a half-written file behind.
public struct AtomicJSONStore: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Encodes `value` and writes it atomically to `fileURL`, creating its folder if needed.
    public func encodeAndWrite<T: Encodable>(_ value: T, to fileURL: URL, using encoder: JSONEncoder = JSONEncoder()) throws {
        let data = try encoder.encode(value)
        try write(data, to: fileURL)
    }

    private func write(_ data: Data, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL)

            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
