import Foundation
import PIPrompts
import PIProviders

/// The `prompt-eval` command. `main.swift` only builds the live instance and exits with `run`'s
/// status; tests build one with a scripted console, providers and environment.
struct PromptEvalCLI: Sendable {
    /// Where the keys are read from.
    var environment: [String: String]
    var console: any EvalConsole
    /// What relative paths, including the default output folder, resolve against.
    var currentDirectory: URL
    /// The client for one provider; called only once the run is confirmed.
    var makeProvider: @Sendable (ProviderID) -> any PromptEngineProvider
    var now: @Sendable () -> Date = { Date() }

    /// The real terminal, environment and API clients.
    static func live() -> PromptEvalCLI {
        let session = ProviderSession.make()
        return PromptEvalCLI(
            environment: ProcessInfo.processInfo.environment,
            console: StandardConsole(),
            currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            makeProvider: { provider in
                switch provider {
                case .anthropic: AnthropicProvider(session: session)
                case .openai: OpenAIProvider(session: session)
                }
            }
        )
    }

    /// Runs the command and returns the exit status.
    func run(_ arguments: [String]) async -> Int32 {
        do {
            let options = try EvalOptions.parse(arguments)
            if options.showHelp {
                console.write(EvalOptions.usage)
                return 0
            }
            switch options.mode {
            case .list:
                try list()
                return 0
            case .check:
                return try check(options)
            case .smoke, .full, .sweep:
                return try await evaluate(options)
            }
        } catch {
            console.writeError("prompt-eval: \(error)")
            if case .usage = error {
                console.writeError("Run `prompt-eval --help` for usage.")
            }
            return 2
        }
    }

    // MARK: - Network modes

    /// smoke, full and sweep: plans the run, shows the cost and asks, then sends every request,
    /// checks and grades the outputs, and writes the results folder and its summary.
    private func evaluate(_ options: EvalOptions) async throws(EvalError) -> Int32 {
        let keys = EvalKeys.read(from: environment)
        guard !keys.isEmpty else {
            throw .missingKeys("""
                No API key found. Set \(EvalKeys.anthropicVariable) and/or \(EvalKeys.openAIVariable) to run \(options.mode.rawValue).
                These are deliberately not the standard variable names, so a key exported for other tools never spends money here.
                Every network mode spends your own API credit; `prompt-eval list` shows what would run, for free.
                """)
        }
        let requested = options.provider.providers
        let available = requested.filter { keys[$0] != nil }
        let skipped = requested.filter { keys[$0] == nil }
        guard !available.isEmpty else {
            let names = skipped.map { EvalKeys.variable(for: $0) }.joined(separator: " and ")
            throw .missingKeys("No key for the requested provider: set \(names).")
        }
        for provider in skipped {
            console.write("Skipping \(provider.displayName): \(EvalKeys.variable(for: provider)) is not set.")
        }

        let resources = try loadResources()
        let plan = try EvalPlan.make(
            mode: options.mode,
            providers: available,
            library: resources.fixtures,
            fixtureIDs: options.fixtureIDs,
            repetitions: options.repetitions,
            judge: options.judge
        )
        if options.judge == true, plan.judge == nil {
            console.write("No key for a judge model, so the judge will not run.")
        }
        printPlan(plan, resources: resources, concurrency: options.concurrency)
        let directory = outputDirectory(options.outputDirectory, suffix: "")
        try refuseToOverwrite(directory)

        if !options.assumeYes {
            console.write("Proceed? This spends your own API credit. [y/N]")
            let answer = console.readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            guard answer == "y" || answer == "yes" else {
                console.write("Nothing was sent.")
                return 1
            }
        }

        try ResultsStore.createDirectory(directory)
        let startedAt = now()
        var info = RunInfo(
            mode: options.mode.rawValue,
            startedAt: startedAt,
            finishedAt: nil,
            repetitions: plan.repetitions,
            fixtureIDs: plan.fixtures.map(\.id),
            configurations: plan.configurations,
            judgeModel: plan.judge?.primary.label,
            crossCheckModel: plan.judge?.crossCheck?.label
        )
        try ResultsStore.writeJSON(info, to: directory.appending(path: ResultsStore.runInfoFile))
        let writer = try ResultsWriter(url: directory.appending(path: ResultsStore.resultsFile))

        let engine = EvalEngine(
            library: resources.packs,
            composer: resources.composer,
            providers: Dictionary(uniqueKeysWithValues: available.map { ($0, makeProvider($0)) }),
            keys: keys.filter { available.contains($0.key) }
        )
        let runner = EvalRunner(engine: engine, judge: plan.judge, concurrency: options.concurrency, now: now)
        let console = console
        let total = plan.jobs.count
        console.write("Writing to \(directory.path(percentEncoded: false))")
        let records = await runner.run(plan.jobs) { record, completed in
            await writer.append(record)
            console.write(Self.progressLine(record, completed: completed, total: total))
        }
        await writer.close()

        var configurationChecks = plan.configurations.map { configuration in
            ConfigurationChecks.prefixMinimum(configuration: configuration, fixtures: plan.fixtures,
                                              library: resources.packs, composer: resources.composer)
        }
        if let probe = plan.cacheProbeFixture {
            console.write("Probing prompt caching (\(plan.configurations.count) × 2 requests)…")
            configurationChecks += await runner.probeCaches(plan.configurations, fixture: probe)
        }
        try ResultsStore.writeJSON(configurationChecks, to: directory.appending(path: ResultsStore.configurationChecksFile))

        info.finishedAt = now()
        try ResultsStore.writeJSON(info, to: directory.appending(path: ResultsStore.runInfoFile))
        let notes = Self.scopeNotes(plan: plan, skipped: skipped, totalFixtures: resources.fixtures.fixtures.count)
        let gate = try writeSummary(info: info, records: records, configurationChecks: configurationChecks,
                                    library: resources.fixtures, notes: notes, directory: directory)
        printVerdict(gate, directory: directory)
        return gate.exitStatus
    }

    // MARK: - Check mode

    /// Re-runs the deterministic checks over a saved `results.jsonl` with the current fixtures and
    /// writes the outcome to a new folder. Cache-read checks are carried over from the original
    /// folder, since they cannot be repeated without sending requests.
    private func check(_ options: EvalOptions) throws(EvalError) -> Int32 {
        guard let path = options.resultsFile else { throw .usage("check needs the path of a results.jsonl file.") }
        let resultsURL = resolve(path)
        let sourceDirectory = resultsURL.deletingLastPathComponent()
        let saved = try ResultsStore.readRecords(at: resultsURL)
        let resources = try loadResources()

        var changed = 0
        var unknown = Set<String>()
        let records = saved.map { record -> RunRecord in
            guard let fixture = resources.fixtures.fixture(withID: record.fixtureID) else {
                unknown.insert(record.fixtureID)
                return record
            }
            var rechecked = record
            rechecked.checks = DeterministicChecks.run(CheckInput(fixture: fixture, record: record))
            if rechecked.deterministicPassed != record.deterministicPassed { changed += 1 }
            return rechecked
        }

        let savedInfo = ResultsStore.readJSON(RunInfo.self, at: sourceDirectory.appending(path: ResultsStore.runInfoFile))
        var configurations: [EvalConfiguration] = []
        for record in records where !configurations.contains(where: { $0.id == record.configuration.id }) {
            configurations.append(record.configuration)
        }
        let fixtureIDs = Array(Set(records.map(\.fixtureID))).sorted()
        let fixtures = fixtureIDs.compactMap(resources.fixtures.fixture(withID:))
        var configurationChecks = configurations.map { configuration in
            ConfigurationChecks.prefixMinimum(configuration: configuration, fixtures: fixtures,
                                              library: resources.packs, composer: resources.composer)
        }
        let savedChecks = ResultsStore.readJSON([ConfigurationCheck].self,
                                                at: sourceDirectory.appending(path: ResultsStore.configurationChecksFile)) ?? []
        configurationChecks += savedChecks.filter { $0.name == ConfigurationChecks.Name.cacheRead }

        let info = RunInfo(
            mode: savedInfo?.mode ?? EvalMode.check.rawValue,
            startedAt: savedInfo?.startedAt ?? now(),
            finishedAt: savedInfo?.finishedAt,
            repetitions: savedInfo?.repetitions ?? (records.map(\.repetition).max() ?? 1),
            fixtureIDs: savedInfo?.fixtureIDs ?? fixtureIDs,
            configurations: savedInfo?.configurations ?? configurations,
            judgeModel: savedInfo?.judgeModel,
            crossCheckModel: savedInfo?.crossCheckModel
        )
        var notes = ["Re-checked from \(resultsURL.path(percentEncoded: false)) with the current fixtures and checks; no request was sent."]
        if !unknown.isEmpty {
            notes.append("Fixtures no longer defined, kept with their saved checks: \(unknown.sorted().joined(separator: ", ")).")
        }
        if savedChecks.isEmpty {
            notes.append("No \(ResultsStore.configurationChecksFile) next to the results, so cache reads are not shown.")
        }

        let directory = outputDirectory(options.outputDirectory, suffix: "-check")
        try refuseToOverwrite(directory)
        try ResultsStore.createDirectory(directory)
        do {
            try ResultsStore.write(try ResultsStore.jsonLines(records), to: directory.appending(path: ResultsStore.resultsFile))
        } catch let error as EvalError {
            throw error
        } catch {
            throw .io("Cannot encode the re-checked results: \(error)")
        }
        try ResultsStore.writeJSON(configurationChecks, to: directory.appending(path: ResultsStore.configurationChecksFile))
        try ResultsStore.writeJSON(info, to: directory.appending(path: ResultsStore.runInfoFile))
        let gate = try writeSummary(info: info, records: records, configurationChecks: configurationChecks,
                                    library: resources.fixtures, notes: notes, directory: directory)
        console.write("Re-checked \(records.count) runs; \(changed) changed between passing and failing.")
        printVerdict(gate, directory: directory)
        return gate.exitStatus
    }

    // MARK: - List mode

    /// Prints the fixtures, the shipped presets, the sweep candidates, the judge and which keys are
    /// set. Sends nothing.
    private func list() throws(EvalError) {
        let resources = try loadResources()
        let fixtures = resources.fixtures.fixtures
        console.write("Fixtures (\(fixtures.count); \(fixtures.count(where: \.inSmoke)) in smoke):")
        let idWidth = (fixtures.map(\.id.count).max() ?? 2) + 2
        console.write("  " + pad("id", idWidth) + pad("target", 9) + pad("lang", 6) + pad("smoke", 7) + pad("words", 7) + "title")
        for fixture in fixtures {
            var title = fixture.title
            if let refine = fixture.refine { title += " [refine: \"\(refine)\"]" }
            console.write("  " + pad(fixture.id, idWidth) + pad(fixture.target, 9) + pad(fixture.expectedLanguage, 6)
                          + pad(fixture.inSmoke ? "yes" : "", 7) + pad(String(TextAnalysis.wordCount(fixture.draft)), 7) + title)
        }

        console.write("")
        console.write("Shipped presets (full runs all three; smoke runs balanced):")
        let presets = ProviderID.allCases.flatMap(EvalConfiguration.shippedPresets(for:))
        printConfigurations(presets, markPresets: false)
        console.write("")
        console.write("Sweep candidates:")
        printConfigurations(ProviderID.allCases.flatMap(EvalConfiguration.sweepCandidates(for:)), markPresets: true)
        console.write("")
        console.write("Judge: \(JudgeModel.anthropic.label) when \(EvalKeys.anthropicVariable) is set, cross-checked by \(JudgeModel.openAI.label) on a 20 % sample when \(EvalKeys.openAIVariable) is also set; \(JudgeModel.openAI.label) alone with only an OpenAI key.")
        let keys = EvalKeys.read(from: environment)
        let keyState = ProviderID.allCases.map { "\(EvalKeys.variable(for: $0)) \(keys[$0] == nil ? "not set" : "set")" }
        console.write("Keys: " + keyState.joined(separator: ", ") + ".")
    }

    private func printConfigurations(_ configurations: [EvalConfiguration], markPresets: Bool) {
        let width = (configurations.map(\.id.count).max() ?? 2) + 2
        for configuration in configurations {
            let price = CostEstimator.prices[configuration.model].map {
                String(format: "$%.2f in / $%.2f out per M tokens", $0.input, $0.output)
            } ?? "no price"
            let same = markPresets ? configuration.preset.map { "  (= \($0.rawValue) preset)" } ?? "" : ""
            console.write("  " + pad(configuration.id, width) + pad(configuration.label, 40) + price + same)
        }
    }

    // MARK: - Shared steps

    private struct Resources {
        var fixtures: FixtureLibrary
        var packs: TargetPackLibrary
        var composer: PromptComposer
    }

    private func loadResources() throws(EvalError) -> Resources {
        let fixtures = try FixtureLibrary.bundled()
        do {
            return Resources(fixtures: fixtures, packs: try TargetPackLibrary.bundled(), composer: try PromptComposer.bundled())
        } catch {
            throw .io("Cannot load the prompt engine's resources: \(error)")
        }
    }

    /// What the run will send and roughly what it will cost, printed before anything is sent.
    private func printPlan(_ plan: EvalPlan, resources: Resources, concurrency: Int) {
        func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }
        console.write("Plan: \(plan.mode.rawValue) — \(count(plan.fixtures.count, "fixture")) × \(count(plan.configurations.count, "configuration")) × \(count(plan.repetitions, "repetition")) = \(count(plan.jobs.count, "run")) (\(count(plan.engineRequestCount, "engine request"))), concurrency \(concurrency).")
        if plan.mode == .sweep, plan.repetitions < 3 {
            console.write("Note: the sweep calls for at least 3 repetitions per cell; this run has \(plan.repetitions).")
        }
        if let judge = plan.judge {
            console.write("Judge: \(judge.primary.label) on every completed run" + (judge.crossCheck.map { ", \($0.label) on \(plan.crossCheckCount) of them" } ?? "") + ".")
        } else {
            console.write("Judge: off (the gate cannot pass without it).")
        }
        console.write("Plus a cache probe per configuration: \(plan.configurations.count * 2) requests.")
        let lines = CostEstimator.lines(for: plan.requestEstimates(library: resources.packs, composer: resources.composer))
        func name(_ line: CostLine) -> String { line.isJudge ? "\(line.model) (judge)" : line.model }
        let width = (lines.map { name($0).count }.max() ?? 5) + 2
        console.write("")
        console.write("  " + pad("model", width) + pad("requests", 10) + pad("input tok", 12) + pad("output tok", 12) + "estimate")
        for line in lines {
            console.write("  " + pad(name(line), width) + pad(String(line.requests), 10) + pad(String(line.inputTokens), 12)
                          + pad(String(line.outputTokens), 12) + CostEstimator.format(line.cost))
        }
        let total = lines.compactMap(\.cost).reduce(0, +)
        console.write("  " + pad("total", width) + pad(String(lines.reduce(0) { $0 + $1.requests }), 10) + pad("", 24) + CostEstimator.format(total))
        console.write("Rough estimate (4 characters a token, a reasoning allowance per effort, no caching discount).")
        console.write("")
    }

    /// Computes each configuration's statistics and the gate verdict, and writes `summary.md`.
    private func writeSummary(
        info: RunInfo,
        records: [RunRecord],
        configurationChecks: [ConfigurationCheck],
        library: FixtureLibrary,
        notes: [String],
        directory: URL
    ) throws(EvalError) -> GateReport {
        var configurations = info.configurations
        for record in records where !configurations.contains(where: { $0.id == record.configuration.id }) {
            configurations.append(record.configuration)
        }
        let stats = configurations.map { configuration in
            ConfigurationStats(configuration: configuration, records: records) { id in
                library.fixture(withID: id)?.isShort ?? false
            }
        }
        var notes = notes
        if info.judgeModel == nil {
            notes.append("The judge did not run, so its criteria are not evaluated and the verdict cannot be PASS.")
        }
        let gate = ShipGate.evaluate(stats: stats, configurationChecks: configurationChecks, notes: notes)
        let summary = SummaryWriter.markdown(SummaryInput(info: info, records: records, configurationChecks: configurationChecks,
                                                          stats: stats, gate: gate))
        try ResultsStore.write(Data(summary.utf8), to: directory.appending(path: ResultsStore.summaryFile))
        return gate
    }

    private func printVerdict(_ gate: GateReport, directory: URL) {
        console.write("")
        console.write("Ship gate: \(gate.verdict.rawValue)")
        for configurationGate in gate.gates where configurationGate.status != .pass {
            let open = configurationGate.criteria.filter { $0.status != .pass }.map { "\($0.name) (\($0.status.label))" }
            console.write("  \(configurationGate.configuration.id): " + open.joined(separator: "; "))
        }
        for note in gate.notes {
            console.write("  \(note)")
        }
        console.write("Summary: \(directory.appending(path: ResultsStore.summaryFile).path(percentEncoded: false))")
    }

    /// Notes for the summary on what the run left out, so a partial run is not read as a full one.
    static func scopeNotes(plan: EvalPlan, skipped: [ProviderID], totalFixtures: Int) -> [String] {
        var notes: [String] = []
        if plan.mode == .smoke {
            notes.append("Smoke covers the Balanced preset over \(plan.fixtures.count) fixtures: a quick health check, not the ship decision (that is `prompt-eval full`).")
        }
        if plan.mode != .smoke, plan.repetitions < 3 {
            notes.append("Only \(plan.repetitions) repetition(s): the gate assumes 3.")
        }
        if plan.mode != .smoke, plan.fixtures.count < totalFixtures {
            notes.append("Only \(plan.fixtures.count) of \(totalFixtures) fixtures were run.")
        }
        for provider in skipped {
            notes.append("\(provider.displayName) was not run (\(EvalKeys.variable(for: provider)) is not set).")
        }
        return notes
    }

    /// The terminal line for a finished run: progress, configuration, fixture, repetition, checks,
    /// timings of the first request and the judge's score.
    static func progressLine(_ record: RunRecord, completed: Int, total: Int) -> String {
        let width = String(total).count
        let counter = "[" + String(repeating: " ", count: max(0, width - String(completed).count)) + "\(completed)/\(total)]"
        var parts = [counter, record.configuration.id, record.fixtureID, "#\(record.repetition)"]
        let failed = record.failedChecks
        parts.append(failed.isEmpty ? "ok \(record.checks.count)/\(record.checks.count)" : "FAIL " + failed.map(\.name).joined(separator: ","))
        if let first = record.turns.first?.measurement {
            parts.append(first.timeToFirstText.map { String(format: "first %.2fs", $0) } ?? "first —")
            parts.append(String(format: "total %.2fs", first.totalTime))
        }
        if let judge = record.judge?.primary {
            parts.append(judge.overall.map { "judge \($0)" } ?? "judge error")
        }
        return parts.joined(separator: "  ")
    }

    // MARK: - Paths

    /// Results cost money: never overwrite a folder that already holds some.
    private func refuseToOverwrite(_ directory: URL) throws(EvalError) {
        let existing = directory.appending(path: ResultsStore.resultsFile)
        if FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)) {
            throw .usage("\(existing.path(percentEncoded: false)) already exists; choose another --out.")
        }
    }

    private func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : currentDirectory.appending(path: expanded)
    }

    /// `--out`, or `./build/eval/<timestamp><suffix>`. Run from the repository root, that lands in
    /// the git-ignored `build/` folder.
    private func outputDirectory(_ option: String?, suffix: String) -> URL {
        if let option { return resolve(option) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return currentDirectory.appending(path: "build/eval/\(formatter.string(from: now()))\(suffix)", directoryHint: .isDirectory)
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
