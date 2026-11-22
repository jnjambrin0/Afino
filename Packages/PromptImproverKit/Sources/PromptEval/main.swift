// prompt-eval: the evaluation harness for Afino's prompt engine. It runs the shipped prompt engine
// and provider clients over the fixtures in Fixtures/, checks every output, can have a second model
// grade it, and writes a report with a ship-gate verdict.
//
// The smoke, full and sweep modes send real requests and spend the caller's own API credit; list
// and check send nothing. `prompt-eval --help` lists the modes and docs/EVALUATION.md explains them.
//
// All logic lives in PromptEvalCLI and the types it uses; this file only runs it.
import Foundation

exit(await PromptEvalCLI.live().run(Array(CommandLine.arguments.dropFirst())))
