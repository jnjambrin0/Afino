import Foundation

/// Every fixture, in file-name order, with variants resolved against their base.
struct FixtureLibrary: Sendable {
    let fixtures: [Fixture]

    /// Resolves variants (draft and target inherited when left out) and rejects repeated ids.
    init(fixtures: [Fixture]) throws(EvalError) {
        var byID: [String: Fixture] = [:]
        for fixture in fixtures {
            guard byID[fixture.id] == nil else { throw .duplicateFixtureID(fixture.id) }
            byID[fixture.id] = fixture
        }
        self.fixtures = try fixtures.map { fixture throws(EvalError) in
            guard let baseID = fixture.variantOf else { return fixture }
            guard let base = byID[baseID], base.variantOf == nil else {
                throw .unknownVariantBase(fixture: fixture.id, base: baseID)
            }
            var resolved = fixture
            if resolved.draft.isEmpty { resolved.draft = base.draft }
            if resolved.target.isEmpty { resolved.target = base.target }
            return resolved
        }
    }

    /// Loads every `*.json` file in `directory`, sorted by file name.
    init(directory: URL) throws(EvalError) {
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw .fixturesMissing
        }
        let decoder = JSONDecoder()
        var fixtures: [Fixture] = []
        for file in files {
            do {
                fixtures.append(try decoder.decode(Fixture.self, from: Data(contentsOf: file)))
            } catch {
                throw .malformedFixture(file: file.lastPathComponent, reason: "\(error)")
            }
        }
        try self.init(fixtures: fixtures)
    }

    /// The fixtures shipped with the tool.
    static func bundled() throws(EvalError) -> FixtureLibrary {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw .fixturesMissing
        }
        return try FixtureLibrary(directory: directory)
    }

    func fixture(withID id: String) -> Fixture? {
        fixtures.first { $0.id == id }
    }

    /// The fixtures `prompt-eval smoke` runs.
    var smoke: [Fixture] { fixtures.filter(\.inSmoke) }

    /// The fixtures with these ids, in library order; throws naming any unknown id.
    func select(_ ids: [String]) throws(EvalError) -> [Fixture] {
        let wanted = Set(ids)
        let known = Set(fixtures.map(\.id))
        let unknown = ids.filter { !known.contains($0) }
        guard unknown.isEmpty else { throw .unknownFixtures(unknown) }
        return fixtures.filter { wanted.contains($0.id) }
    }
}
