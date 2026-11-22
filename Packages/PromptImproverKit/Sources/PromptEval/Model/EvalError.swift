import Foundation

/// Why the harness could not do what it was asked. Each case reads as one line for the terminal.
enum EvalError: Error, Sendable, Equatable, CustomStringConvertible {
    case usage(String)
    case missingKeys(String)
    case fixturesMissing
    case malformedFixture(file: String, reason: String)
    case duplicateFixtureID(String)
    case unknownVariantBase(fixture: String, base: String)
    case unknownFixtures([String])
    case unreadableResults(path: String, reason: String)
    case io(String)

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .missingKeys(let message):
            message
        case .fixturesMissing:
            "The bundled Fixtures folder is missing (a packaging problem with the prompt-eval target)."
        case .malformedFixture(let file, let reason):
            "Fixture \(file) is malformed: \(reason)"
        case .duplicateFixtureID(let id):
            "Two fixtures declare the id '\(id)'."
        case .unknownVariantBase(let fixture, let base):
            "Fixture '\(fixture)' is a variant of '\(base)', which does not exist or is itself a variant."
        case .unknownFixtures(let ids):
            "Unknown fixture id(s): \(ids.joined(separator: ", ")). Run `prompt-eval list` to see them."
        case .unreadableResults(let path, let reason):
            "Cannot read results from \(path): \(reason)"
        case .io(let message):
            message
        }
    }
}
