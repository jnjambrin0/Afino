import Foundation

/// Reading and writing the files in an output folder.
enum ResultsStore {
    static let resultsFile = "results.jsonl"
    static let summaryFile = "summary.md"
    static let runInfoFile = "run.json"
    static let configurationChecksFile = "configuration-checks.json"

    /// Sorted keys and ISO 8601 dates, so result files compare cleanly between runs.
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// One record per line, in the order given.
    static func jsonLines(_ records: [RunRecord]) throws -> Data {
        var data = Data()
        let encoder = encoder()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        return data
    }

    static func readRecords(at url: URL) throws(EvalError) -> [RunRecord] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw .unreadableResults(path: url.path(percentEncoded: false), reason: error.localizedDescription)
        }
        let decoder = decoder()
        var records: [RunRecord] = []
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            do {
                records.append(try decoder.decode(RunRecord.self, from: Data(line.utf8)))
            } catch {
                throw .unreadableResults(path: url.path(percentEncoded: false), reason: "line \(number + 1) is not a run record (\(error))")
            }
        }
        return records
    }

    static func write(_ data: Data, to url: URL) throws(EvalError) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .io("Cannot write \(url.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }

    static func writeJSON(_ value: some Encodable, to url: URL) throws(EvalError) {
        let data: Data
        do {
            data = try encoder(pretty: true).encode(value)
        } catch {
            throw .io("Cannot encode \(url.lastPathComponent): \(error)")
        }
        try write(data, to: url)
    }

    /// Nil when the file is missing or does not decode; used for optional companions of a results file.
    static func readJSON<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(type, from: data)
    }

    static func createDirectory(_ url: URL) throws(EvalError) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw .io("Cannot create \(url.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }
}

/// Appends records to `results.jsonl` as they complete, so an interrupted run keeps what it has.
actor ResultsWriter {
    private let handle: FileHandle
    private let encoder = ResultsStore.encoder()

    init(url: URL) throws(EvalError) {
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil),
              let handle = try? FileHandle(forWritingTo: url)
        else {
            throw .io("Cannot create \(url.path(percentEncoded: false))")
        }
        self.handle = handle
    }

    func append(_ record: RunRecord) {
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)
        try? handle.write(contentsOf: data)
    }

    func close() {
        try? handle.close()
    }
}
