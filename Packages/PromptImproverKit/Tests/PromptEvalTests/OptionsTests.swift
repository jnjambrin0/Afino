import Foundation
import PIProviders
import Testing
@testable import PromptEval

/// Command-line parsing and where keys come from.
struct OptionsTests {
    @Test
    func modesAndDefaults() throws {
        let smoke = try EvalOptions.parse(["smoke"])
        #expect(smoke.mode == .smoke)
        #expect(smoke.provider == .all)
        #expect(smoke.concurrency == 3)
        #expect(smoke.judge == nil)
        #expect(!smoke.assumeYes)
        #expect(try EvalOptions.parse(["list"]).mode == .list)
        #expect(try EvalOptions.parse(["--help"]).showHelp)
    }

    @Test
    func everyOption() throws {
        let options = try EvalOptions.parse([
            "full", "--provider", "openai", "--fixtures", "es-email, img-en", "--repetitions", "5",
            "--out", "build/eval/x", "--no-judge", "--yes", "--concurrency", "6",
        ])
        #expect(options.mode == .full)
        #expect(options.provider == .openai)
        #expect(options.fixtureIDs == ["es-email", "img-en"])
        #expect(options.repetitions == 5)
        #expect(options.outputDirectory == "build/eval/x")
        #expect(options.judge == false)
        #expect(options.assumeYes)
        #expect(options.concurrency == 6)
        #expect(try EvalOptions.parse(["sweep", "--judge"]).judge == true)
    }

    @Test
    func checkTakesAResultsFile() throws {
        let options = try EvalOptions.parse(["check", "build/eval/1/results.jsonl", "--out", "/tmp/x"])
        #expect(options.mode == .check)
        #expect(options.resultsFile == "build/eval/1/results.jsonl")
        #expect(options.outputDirectory == "/tmp/x")
    }

    @Test(arguments: [
        [String](),
        ["nonsense"],
        ["smoke", "--provider", "google"],
        ["smoke", "--repetitions", "0"],
        ["smoke", "--concurrency", "lots"],
        ["smoke", "--fixtures"],
        ["smoke", "--out", "--yes"],
        ["smoke", "--frobnicate"],
        ["check"],
        ["smoke", "extra"],
    ])
    func badArgumentsAreUsageErrors(_ arguments: [String]) {
        #expect {
            try EvalOptions.parse(arguments)
        } throws: { error in
            guard let error = error as? EvalError, case .usage = error else { return false }
            return true
        }
    }

    @Test
    func keysComeOnlyFromTheHarnessVariables() {
        let environment = [
            "ANTHROPIC_API_KEY": "sk-ant-standard-variable-0000",
            "OPENAI_API_KEY": "sk-standard-variable-0000",
        ]
        #expect(EvalKeys.read(from: environment).isEmpty, "the standard variable names never spend money here")
        let keys = EvalKeys.read(from: ["PI_LIVE_ANTHROPIC_KEY": "  sk-ant-test-1234567890 \n", "PI_LIVE_OPENAI_KEY": "   "])
        #expect(keys.count == 1)
        #expect(keys[.anthropic]?.rawValue == "sk-ant-test-1234567890")
        #expect("\(keys[.anthropic]!)" == "sk-…7890", "a key never prints in full")
    }
}
