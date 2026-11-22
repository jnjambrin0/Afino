import Foundation
import PIProviders

/// The `--provider` choice: which providers a network mode runs.
enum ProviderFilter: String, Sendable, Hashable, CaseIterable {
    case anthropic
    case openai
    case all

    var providers: [ProviderID] {
        switch self {
        case .anthropic: [.anthropic]
        case .openai: [.openai]
        case .all: [.anthropic, .openai]
        }
    }
}

/// The parsed command line.
struct EvalOptions: Sendable, Hashable {
    var mode: EvalMode
    var provider: ProviderFilter = .all
    /// Nil runs the mode's default fixtures.
    var fixtureIDs: [String]?
    /// Nil follows the mode's default (1 for smoke, 3 for full and sweep).
    var repetitions: Int?
    /// Nil writes to a new timestamped folder under `./build/eval/`.
    var outputDirectory: String?
    /// Nil follows the mode's default (on for full and sweep, off for smoke).
    var judge: Bool?
    var assumeYes = false
    var concurrency = 3
    /// `check` only: the results file to re-check.
    var resultsFile: String?
    var showHelp = false

    init(mode: EvalMode) {
        self.mode = mode
    }

    static let usage = """
        prompt-eval: quality and latency checks of Afino's prompt engine against the real APIs.

        smoke, full and sweep send real requests and spend your own API credit. Each one first
        prints the plan with a rough cost estimate and asks before sending anything (unless
        --yes). list and check send nothing and need no key.

        Keys are read only from PI_LIVE_ANTHROPIC_KEY and PI_LIVE_OPENAI_KEY, never from
        ANTHROPIC_API_KEY or OPENAI_API_KEY, so a key exported for other tools is never spent here.

        Usage, from the repository root:
          swift run --package-path Packages/PromptImproverKit prompt-eval <mode> [options]

        Modes:
          smoke    The 8 smoke fixtures × each provider's Balanced preset, 1 repetition, no judge.
                   A quick health check after a change to the prompts or the provider code.
          full     Every fixture × the Fast, Balanced and Quality presets, 3 repetitions, judged.
                   The ship decision.
          sweep    Every fixture × the candidate configurations, 3 repetitions, judged.
                   Used to choose the preset defaults.
          list     The fixtures, presets and sweep candidates. Sends nothing.
          check <results.jsonl>
                   Re-runs the deterministic checks over saved outputs and writes a new summary.
                   Sends nothing; only --out applies.

        Options:
          --provider anthropic|openai|all   providers to run (default: every one that has a key)
          --fixtures id,id                  only these fixtures (ids from `prompt-eval list`)
          --repetitions N                   repetitions per fixture and configuration
          --out <dir>                       output folder (default: ./build/eval/<timestamp>);
                                            a folder that already holds results is refused
          --judge, --no-judge               grade outputs with the rubric judge (default: on for
                                            full and sweep, off for smoke)
          --concurrency N                   requests in flight at once (default: 3)
          --yes, -y                         skip the confirmation
          --help, -h                        show this text

        Exit status: 0 when the ship gate passes (and for list and --help), 1 when it fails, is
        incomplete or the run is declined, 2 for a usage error or missing keys.

        docs/EVALUATION.md explains the checks, the judge, the ship gate and how to add a fixture.
        """

    /// Parses the arguments after the executable name.
    static func parse(_ arguments: [String]) throws(EvalError) -> EvalOptions {
        guard let first = arguments.first else {
            throw .usage("Choose a mode: smoke, full, sweep, list or check.")
        }
        if first == "--help" || first == "-h" || first == "help" {
            var options = EvalOptions(mode: .list)
            options.showHelp = true
            return options
        }
        guard let mode = EvalMode(rawValue: first) else {
            throw .usage("Unknown mode '\(first)'. Choose smoke, full, sweep, list or check.")
        }
        var options = EvalOptions(mode: mode)
        var rest = arguments.dropFirst().makeIterator()

        func value(for flag: String) throws(EvalError) -> String {
            guard let value = rest.next(), !value.hasPrefix("--") else {
                throw .usage("\(flag) needs a value.")
            }
            return value
        }
        func positive(_ text: String, for flag: String) throws(EvalError) -> Int {
            guard let number = Int(text), number > 0 else {
                throw .usage("\(flag) needs a positive whole number, not '\(text)'.")
            }
            return number
        }

        while let argument = rest.next() {
            switch argument {
            case "--provider":
                let text = try value(for: argument)
                guard let filter = ProviderFilter(rawValue: text.lowercased()) else {
                    throw .usage("--provider must be anthropic, openai or all, not '\(text)'.")
                }
                options.provider = filter
            case "--fixtures":
                let ids = try value(for: argument).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !ids.isEmpty else { throw .usage("--fixtures needs at least one fixture id.") }
                options.fixtureIDs = ids
            case "--repetitions":
                options.repetitions = try positive(try value(for: argument), for: argument)
            case "--out":
                options.outputDirectory = try value(for: argument)
            case "--judge":
                options.judge = true
            case "--no-judge":
                options.judge = false
            case "--yes", "-y":
                options.assumeYes = true
            case "--concurrency":
                options.concurrency = try positive(try value(for: argument), for: argument)
            case "--help", "-h":
                options.showHelp = true
            default:
                if mode == .check, options.resultsFile == nil, !argument.hasPrefix("-") {
                    options.resultsFile = argument
                } else {
                    throw .usage("Unknown argument '\(argument)'.")
                }
            }
        }
        if mode == .check, options.resultsFile == nil, !options.showHelp {
            throw .usage("check needs the path of a results.jsonl file.")
        }
        return options
    }
}

/// The API keys, read only from the harness's own variables.
///
/// Deliberately not `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`: a key exported for other tools must
/// never make this tool spend money by accident.
enum EvalKeys {
    static let anthropicVariable = "PI_LIVE_ANTHROPIC_KEY"
    static let openAIVariable = "PI_LIVE_OPENAI_KEY"

    static func variable(for provider: ProviderID) -> String {
        switch provider {
        case .anthropic: anthropicVariable
        case .openai: openAIVariable
        }
    }

    /// The keys that are set; a blank value counts as unset.
    static func read(from environment: [String: String]) -> [ProviderID: APIKey] {
        var keys: [ProviderID: APIKey] = [:]
        for provider in ProviderID.allCases {
            if let raw = environment[variable(for: provider)] {
                let key = APIKey(raw)
                if !key.isEmpty { keys[provider] = key }
            }
        }
        return keys
    }
}
