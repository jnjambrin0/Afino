import Foundation
import PIPrompts
import PIProviders
import Synchronization
import Testing
@testable import PromptEval

/// The runner and the whole command, against scripted in-process providers: no network.
struct EndToEndTests {
    static let anthropicKey = "sk-ant-test-key-0000-SECRET"
    static let openAIKey = "sk-test-key-0000-SECRET"

    static let goodEmail = """
        Redacta un correo breve y educado para mi casero en el que le pida que arregle la caldera, que ha dejado de funcionar. \
        Explica el problema con claridad, pide que la reparación se haga lo antes posible y ofrece facilitar el acceso a la vivienda. \
        Indica [desde cuándo falla la caldera] para dar contexto.
        """

    /// The scripted engine: a good prompt for es-email, the draft itself for anything else, and
    /// a passing grade for the judge.
    @Sendable static func respond(_ request: EngineRequest) -> ScriptedReply {
        if isJudgeRequest(request) { return .text(judgeReply(overall: 5)) }
        guard let draft = draft(in: request) else { return .text("Write a short poem.") }
        return .text(draft.contains("casero") ? goodEmail : draft)
    }

    /// Builds the command with scripted providers and counts how often a provider is made.
    final class Harness: Sendable {
        let providers: [ProviderID: ScriptedProvider]
        let made = Mutex(0)
        let console: TestConsole
        let directory: URL

        init(input: [String] = [], respond: @escaping @Sendable (EngineRequest) -> ScriptedReply = EndToEndTests.respond) throws {
            providers = [.anthropic: ScriptedProvider(id: .anthropic, respond: respond),
                         .openai: ScriptedProvider(id: .openai, respond: respond)]
            console = TestConsole(input: input)
            directory = try temporaryDirectory()
        }

        func cli(environment: [String: String]) -> PromptEvalCLI {
            PromptEvalCLI(
                environment: environment,
                console: console,
                currentDirectory: directory,
                makeProvider: { [self] id in
                    made.withLock { $0 += 1 }
                    return providers[id]!
                }
            )
        }

        var requestCount: Int { providers.values.reduce(0) { $0 + $1.requests.count } }

        func file(_ name: String, in folder: String = "out") -> URL {
            directory.appending(path: folder).appending(path: name)
        }
    }

    static let bothKeys = ["PI_LIVE_ANTHROPIC_KEY": anthropicKey, "PI_LIVE_OPENAI_KEY": openAIKey]

    // MARK: - The command

    @Test
    func aScriptedSmokeRunWritesResultsAndSummary() async throws {
        let harness = try Harness()
        let status = await harness.cli(environment: Self.bothKeys).run(["smoke", "--yes", "--out", "out"])

        #expect(status == 1, "smoke without the judge cannot pass the gate")
        let lines = try String(contentsOf: harness.file("results.jsonl"), encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 16, "8 smoke fixtures × the balanced preset of 2 providers")
        let records = try ResultsStore.readRecords(at: harness.file("results.jsonl"))
        #expect(Set(records.map(\.configuration.id)) == ["anthropic/balanced", "openai/balanced"])
        #expect(Set(records.map(\.fixtureID)) == Set(Shipped.fixtures.smoke.map(\.id)))
        #expect(records.allSatisfy { !$0.checks.isEmpty && $0.judge == nil })
        #expect(records.allSatisfy { $0.turns.first?.measurement.servedModel == "scripted-model" })
        let email = try #require(records.first { $0.fixtureID == "es-email" })
        #expect(email.output == Self.goodEmail)
        #expect(email.deterministicPassed, "\(email.failedChecks)")
        #expect(email.turns[0].measurement.usage?.cacheReadInputTokens == 2_000)

        #expect(harness.requestCount == 16 + 2 * 2, "runs plus two cache-probe requests per configuration")
        let summary = try String(contentsOf: harness.file("summary.md"), encoding: .utf8)
        #expect(summary.contains("# prompt-eval: smoke"))
        #expect(summary.contains("## Ship gate: INCOMPLETE"))
        #expect(summary.contains("## Configurations"))
        #expect(summary.contains("| anthropic/balanced | claude-sonnet-5-5 · low | 8 |"))
        #expect(summary.contains("cache_read | pass"))
        let checks = try #require(ResultsStore.readJSON([ConfigurationCheck].self, at: harness.file("configuration-checks.json")))
        #expect(checks.count == 4)
        #expect(checks.allSatisfy { $0.status == .pass })
        let info = try #require(ResultsStore.readJSON(RunInfo.self, at: harness.file("run.json")))
        #expect(info.mode == "smoke")
        #expect(info.finishedAt != nil)

        #expect(harness.console.output.contains("Ship gate: INCOMPLETE"))
        #expect(harness.console.output.contains("[16/16]"))
        for key in [Self.anthropicKey, Self.openAIKey] {
            #expect(!harness.console.output.contains(key))
            #expect(!harness.console.errors.contains(key))
            #expect(!summary.contains(key))
            #expect(try !String(contentsOf: harness.file("results.jsonl"), encoding: .utf8).contains(key))
        }
        #expect(harness.providers[.anthropic]!.keys.allSatisfy { $0 == Self.anthropicKey })
        #expect(harness.providers[.openai]!.keys.allSatisfy { $0 == Self.openAIKey })
    }

    @Test
    func aCleanJudgedRunPassesTheGate() async throws {
        let harness = try Harness()
        let status = await harness.cli(environment: ["PI_LIVE_ANTHROPIC_KEY": Self.anthropicKey])
            .run(["smoke", "--fixtures", "es-email", "--judge", "--yes", "--out", "out"])
        let summary = try String(contentsOf: harness.file("summary.md"), encoding: .utf8)
        #expect(status == 0, "\(summary)")
        #expect(summary.contains("## Ship gate: PASS"))
        #expect(summary.contains("## Judge"))
        let records = try ResultsStore.readRecords(at: harness.file("results.jsonl"))
        #expect(records.count == 1)
        #expect(records[0].judge?.primary.overall == 5)
        #expect(records[0].judge?.crossCheck == nil, "no OpenAI key, no cross-check")
        #expect(harness.providers[.openai]!.requests.isEmpty)
    }

    @Test
    func networkModesWithoutKeysExitTwo() async throws {
        for mode in ["smoke", "full", "sweep"] {
            let harness = try Harness()
            let status = await harness.cli(environment: ["ANTHROPIC_API_KEY": "sk-ant-standard", "OPENAI_API_KEY": "sk-standard"])
                .run([mode, "--yes"])
            #expect(status == 2)
            #expect(harness.console.errors.contains("PI_LIVE_ANTHROPIC_KEY"))
            #expect(harness.console.errors.contains("PI_LIVE_OPENAI_KEY"))
            #expect(harness.made.withLock { $0 } == 0)
            #expect(harness.requestCount == 0)
        }
    }

    @Test
    func aProviderWithoutItsKeyExitsTwo() async throws {
        let harness = try Harness()
        let status = await harness.cli(environment: ["PI_LIVE_ANTHROPIC_KEY": Self.anthropicKey]).run(["smoke", "--provider", "openai", "--yes"])
        #expect(status == 2)
        #expect(harness.console.errors.contains("PI_LIVE_OPENAI_KEY"))
        #expect(harness.requestCount == 0)
    }

    @Test
    func decliningSendsNothing() async throws {
        let harness = try Harness(input: ["n"])
        let status = await harness.cli(environment: Self.bothKeys).run(["full", "--out", "out"])
        #expect(status == 1)
        #expect(harness.requestCount == 0)
        #expect(harness.console.output.contains("Plan: full — 31 fixtures × 6 configurations × 3 repetitions"))
        #expect(harness.console.output.contains("claude-opus-5-5 (judge)"))
        #expect(harness.console.output.contains("Nothing was sent."))
        #expect(!FileManager.default.fileExists(atPath: harness.directory.appending(path: "out").path(percentEncoded: false)))
    }

    @Test
    func listNeedsNoKeys() async throws {
        let harness = try Harness()
        let status = await harness.cli(environment: [:]).run(["list"])
        #expect(status == 0)
        #expect(harness.made.withLock { $0 } == 0)
        let output = harness.console.output
        for fixture in Shipped.fixtures.fixtures {
            #expect(output.contains(fixture.id))
        }
        for configuration in ProviderID.allCases.flatMap(EvalConfiguration.sweepCandidates(for:)) {
            #expect(output.contains(configuration.id))
        }
        #expect(output.contains("anthropic/balanced"))
        #expect(output.contains("PI_LIVE_ANTHROPIC_KEY not set"))
    }

    @Test
    func checkReRunsTheChecksWithoutTheNetwork() async throws {
        let harness = try Harness()
        _ = await harness.cli(environment: Self.bothKeys).run(["smoke", "--yes", "--out", "out"])
        let requestsBefore = harness.requestCount

        // Corrupt one saved output, as if an older engine had produced it.
        var records = try ResultsStore.readRecords(at: harness.file("results.jsonl"))
        let index = try #require(records.firstIndex { $0.fixtureID == "es-email" })
        #expect(records[index].deterministicPassed)
        records[index].output = "Sure! " + records[index].output
        try ResultsStore.jsonLines(records).write(to: harness.file("results.jsonl"))

        let status = await harness.cli(environment: [:]).run(["check", "out/results.jsonl", "--out", "rechecked"])
        #expect(status == 1)
        #expect(harness.requestCount == requestsBefore, "check sends nothing")
        let rechecked = try ResultsStore.readRecords(at: harness.file("results.jsonl", in: "rechecked"))
        #expect(rechecked.count == records.count)
        #expect(rechecked[index].failedChecks.map(\.name) == [DeterministicChecks.Name.noPrefaceOrCommentary])
        let summary = try String(contentsOf: harness.file("summary.md", in: "rechecked"), encoding: .utf8)
        #expect(summary.contains("Re-checked from"))
        #expect(summary.contains("cache_read"), "cache probes are carried over from the original folder")
        #expect(harness.console.output.contains("changed between passing and failing"))
    }

    @Test
    func existingResultsAreNeverOverwritten() async throws {
        let harness = try Harness()
        #expect(await harness.cli(environment: Self.bothKeys).run(["smoke", "--yes", "--out", "out"]) == 1)
        let saved = try Data(contentsOf: harness.file("results.jsonl"))
        let requests = harness.requestCount

        #expect(await harness.cli(environment: Self.bothKeys).run(["smoke", "--yes", "--out", "out"]) == 2)
        #expect(harness.console.errors.contains("already exists; choose another --out"))
        #expect(harness.requestCount == requests, "nothing was sent")
        #expect(await harness.cli(environment: [:]).run(["check", "out/results.jsonl", "--out", "out"]) == 2)
        #expect(try Data(contentsOf: harness.file("results.jsonl")) == saved)
    }

    @Test
    func checkOfAMissingFileExitsTwo() async throws {
        let harness = try Harness()
        #expect(await harness.cli(environment: [:]).run(["check", "nowhere/results.jsonl"]) == 2)
        #expect(harness.console.errors.contains("Cannot read results"))
    }

    // MARK: - The runner

    private func runner(_ respond: @escaping @Sendable (EngineRequest) -> ScriptedReply, judge: JudgeSetup? = nil) -> (EvalRunner, ScriptedProvider) {
        let provider = ScriptedProvider(id: .anthropic, respond: respond)
        let engine = EvalEngine(library: Shipped.packs, composer: Shipped.composer, providers: [.anthropic: provider],
                                keys: [.anthropic: APIKey(Self.anthropicKey)])
        return (EvalRunner(engine: engine, judge: judge, concurrency: 2), provider)
    }

    private func job(_ fixtureID: String, _ tier: PresetTier = .balanced) -> EvalJob {
        EvalJob(index: 0, fixture: Shipped.fixture(fixtureID), configuration: .shipped(tier, provider: .anthropic), repetition: 1)
    }

    @Test
    func aRefinementSendsASecondTurnAndChecksTheRevision() async throws {
        let revised = "Plan a front-desk check-in app for a bouldering gym that runs on the Raspberry Pi 4, works offline, speaks Spanish and Catalan, keeps check-in under 90 seconds, exports monthly visits for Ilse, may add sign-ups to Mailchimp later, takes no payments, and is live by June 3."
        let (runner, provider) = runner { request in
            request.turns.count == 1 ? .text("\n" + (draft(in: request) ?? "") + "\n") : .text(revised)
        }
        let record = await runner.run(job("en-long-messy-refine-shorter"))
        #expect(record.turns.count == 2)
        #expect(record.turns[1].instruction == "más corto")
        let fixture = Shipped.fixture("en-long-messy-refine-shorter")
        #expect(record.firstOutput == fixture.draft, "the shown first output is post-processed (trimmed)")
        #expect(record.output == revised)
        #expect(record.deterministicPassed, "\(record.failedChecks)")
        let second = try #require(provider.requests.last)
        #expect(second.turns.count == 3)
        #expect(second.turns[1] == .assistant(fixture.draft))
        #expect(second.systemBlocks == provider.requests[0].systemBlocks)
    }

    @Test
    func theShippedPostProcessorRunsBeforeTheChecks() async {
        let prompt = "Explain Kubernetes to me as a backend developer who has only ever deployed to Heroku: what it does, which Heroku ideas map onto it, and what is genuinely new."
        let (prefaced, _) = runner { _ in .text("Here is the improved prompt:\n\n" + prompt) }
        let stripped = await prefaced.run(job("en-casual"))
        #expect(stripped.output == prompt)
        #expect(stripped.turns[0].measurement.strippedPreface)
        #expect(stripped.deterministicPassed, "\(stripped.failedChecks)")

        let (fenced, _) = runner { _ in .text("```\n" + prompt + "\n```") }
        let unwrapped = await fenced.run(job("en-casual"))
        #expect(unwrapped.output == prompt)
        #expect(unwrapped.turns[0].measurement.unwrappedFence)

        let (chatty, _) = runner { _ in .text("Sure! " + prompt + "\n\nLet me know if you'd like any changes.") }
        let caught = await chatty.run(job("en-casual"))
        #expect(caught.failedChecks.map(\.name) == [DeterministicChecks.Name.noPrefaceOrCommentary])
    }

    @Test
    func aFailedRequestIsRecordedByCaseWithoutTheDraft() async throws {
        let failure = EngineFailure(.rateLimited(retryAfter: .seconds(30)), provider: .anthropic, requestID: "req_429", httpStatus: 429)
        let (runner, _) = runner({ _ in
            .failing(failure, after: [.retrying(attempt: 2, after: .milliseconds(1), reason: .rateLimited)])
        }, judge: JudgeSetup(primary: .anthropic))
        let record = await runner.run(job("es-email"))
        let measurement = try #require(record.turns.first?.measurement)
        #expect(measurement.error == ErrorRecord(name: "rateLimited", requestID: "req_429", httpStatus: 429))
        #expect(measurement.retries == 1)
        #expect(measurement.timeToFirstEvent != nil)
        #expect(measurement.timeToFirstText == nil)
        #expect(record.checks == [.fail(DeterministicChecks.Name.completed, "rateLimited [request req_429]")])
        #expect(record.judge == nil, "only completed runs are graded")
        let json = String(decoding: try ResultsStore.encoder().encode(record), as: UTF8.self)
        #expect(!json.contains("casero"), "the draft never appears in a failure record")
        #expect(!json.contains(Self.anthropicKey))
    }

    @Test
    func anUnusableJudgeVerdictIsRetriedOnce() async {
        let attempts = Counter()
        let (flaky, _) = runner({ request in
            guard isJudgeRequest(request) else { return .text(Self.goodEmail) }
            attempts.record(1)
            return attempts.values.count == 1 ? .text("Looks good to me!") : .text(judgeReply(overall: 4))
        }, judge: JudgeSetup(primary: .anthropic))
        let graded = await flaky.run(job("es-email"))
        #expect(graded.judge?.primary.overall == 4)
        #expect(graded.judge?.primary.error == nil)
        #expect(attempts.values.count == 2)

        let broken = Counter()
        let (failing, _) = runner({ request in
            guard isJudgeRequest(request) else { return .text(Self.goodEmail) }
            broken.record(1)
            return .text("no JSON here")
        }, judge: JudgeSetup(primary: .anthropic))
        let ungraded = await failing.run(job("es-email"))
        #expect(broken.values.count == EvalRunner.judgeAttempts)
        #expect(ungraded.judge?.primary.error == "the judge reply is not a JSON object")
        #expect(ungraded.deterministicPassed, "a judge failure never touches the run itself")
    }

    @Test
    func aCrossCheckGradesTheSampledRuns() async throws {
        let (runner, provider) = runner({ request in
            isJudgeRequest(request) ? .text(judgeReply(overall: 5)) : .text(Self.goodEmail)
        }, judge: JudgeSetup(primary: .anthropic, crossCheck: JudgeModel(provider: .anthropic, model: "claude-sonnet-5-5", effort: .low),
                             crossCheckFraction: 1))
        let record = await runner.run(job("es-email"))
        #expect(record.judge?.crossCheck?.model == "claude-sonnet-5-5")
        #expect(provider.requests.filter(isJudgeRequest).map(\.model) == ["claude-opus-5-5", "claude-sonnet-5-5"])
    }

    @Test
    func truncatedAndRefusedAnswersFail() async {
        let (truncated, _) = runner { _ in .text("Redacta un correo", finish: .truncated) }
        #expect(await truncated.run(job("es-email")).checks == [.fail(DeterministicChecks.Name.completed, "finished as truncated")])
        let (refused, _) = runner { _ in .text("", finish: .refused(category: "cyber")) }
        #expect(await refused.run(job("es-email")).checks == [.fail(DeterministicChecks.Name.completed, "finished as refused(cyber)")])
    }

    @Test
    func timingsAreMeasuredInOrder() async throws {
        let (runner, _) = runner { _ in
            ScriptedReply(events: [.started(servedModel: "claude-sonnet-5-5", requestID: "req_1"), .thinking,
                                   .textDelta("Redacta un correo para el casero "), .textDelta("sobre la caldera."),
                                   .finished(.complete, usage: TokenUsage(inputTokens: 10, outputTokens: 5, reasoningTokens: 3))])
        }
        let record = await runner.run(job("es-email"))
        let measurement = try #require(record.turns.first?.measurement)
        #expect(record.output == "Redacta un correo para el casero sobre la caldera.")
        let firstEvent = try #require(measurement.timeToFirstEvent)
        let firstText = try #require(measurement.timeToFirstText)
        #expect(firstEvent <= firstText)
        #expect(firstText <= measurement.totalTime)
        #expect(measurement.requestID == "req_1")
        #expect(measurement.finishReason == "complete")
        #expect(measurement.usage == UsageRecord(inputTokens: 10, outputTokens: 5, reasoningTokens: 3))
        #expect(measurement.outputCharacters == record.output.count)
    }

    @Test
    func theRunnerKeepsJobOrderAndRespectsConcurrency() async throws {
        let provider = SlowProvider()
        let engine = EvalEngine(library: Shipped.packs, composer: Shipped.composer, providers: [.openai: provider],
                                keys: [.openai: APIKey(Self.openAIKey)])
        let plan = try EvalPlan.make(mode: .full, providers: [.openai], library: Shipped.fixtures,
                                     fixtureIDs: ["es-email", "img-en", "minimal-qq"], repetitions: 1, judge: false)
        let completed = Counter()
        let records = await EvalRunner(engine: engine, judge: nil, concurrency: 2).run(plan.jobs) { _, count in
            completed.record(count)
        }
        #expect(records.count == 9)
        #expect(completed.values.sorted() == Array(1...9))
        #expect(records.map(\.fixtureID) == plan.jobs.map(\.fixture.id))
        #expect(records.map(\.configuration.id) == plan.jobs.map(\.configuration.id))
        #expect(provider.peak <= 2)
        #expect(provider.peak >= 1)
    }

    @Test
    func cacheProbesSendTheSameRequestTwice() async throws {
        let (runner, provider) = runner { _ in .text("Escribe un poema.") }
        let check = await runner.probeCache(configuration: .shipped(.quality, provider: .anthropic), fixture: Shipped.fixture("minimal-poema"))
        #expect(check.status == .pass)
        #expect(check.name == ConfigurationChecks.Name.cacheRead)
        #expect(provider.requests.count == 2)
        #expect(provider.requests[0] == provider.requests[1])

        let (silent, _) = self.runner { _ in .text("Escribe un poema.", usage: nil) }
        #expect(await silent.probeCache(configuration: .shipped(.fast, provider: .anthropic), fixture: Shipped.fixture("minimal-poema")).status == .warning)
        let (cold, _) = self.runner { _ in .text("Escribe un poema.", usage: TokenUsage(inputTokens: 900, outputTokens: 20, cacheReadInputTokens: 0)) }
        #expect(await cold.probeCache(configuration: .shipped(.fast, provider: .anthropic), fixture: Shipped.fixture("minimal-poema")).status == .fail)
    }

    @Test
    func everyShippedPrefixIsLargeEnoughToCache() {
        for provider in ProviderID.allCases {
            let configuration = EvalConfiguration.shipped(.balanced, provider: provider)
            let check = ConfigurationChecks.prefixMinimum(configuration: configuration, fixtures: Shipped.fixtures.fixtures,
                                                          library: Shipped.packs, composer: Shipped.composer)
            #expect(check.status == .pass, "\(check.detail)")
            #expect(check.detail.contains("characters ÷ 4"))
        }
        // A core far too small to cache, with the smallest pack, falls short of OpenAI's minimum.
        let tiny = ConfigurationChecks.prefixMinimum(
            configuration: .shipped(.balanced, provider: .openai), fixtures: [Shipped.fixture("minimal-qq")],
            library: Shipped.packs, composer: PromptComposer(core: "Rewrite the draft."))
        #expect(tiny.status == .fail)
    }
}

/// A thread-safe log of values: the completion counts the runner reports, or one entry per judge
/// attempt.
final class Counter: Sendable {
    private let state = Mutex<[Int]>([])
    func record(_ value: Int) { state.withLock { $0.append(value) } }
    var values: [Int] { state.withLock { $0 } }
}

/// A provider that answers after a short pause and records how many requests overlap.
final class SlowProvider: PromptEngineProvider, Sendable {
    let id: ProviderID = .openai
    private let inFlight = Mutex<(now: Int, peak: Int)>((0, 0))

    var peak: Int { inFlight.withLock { $0.peak } }

    func stream(_ request: EngineRequest, key: APIKey) -> AsyncThrowingStream<EngineEvent, any Error> {
        let output = draft(in: request) ?? "?"
        return AsyncThrowingStream { continuation in
            let task = Task {
                self.inFlight.withLock { state in
                    state.now += 1
                    state.peak = max(state.peak, state.now)
                }
                try? await Task.sleep(for: .milliseconds(20))
                continuation.yield(.started(servedModel: request.model, requestID: nil))
                continuation.yield(.textDelta(output))
                continuation.yield(.finished(.complete, usage: nil))
                self.inFlight.withLock { $0.now -= 1 }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func models(key: APIKey) async throws -> [RemoteModel] { [] }
    func prewarm() async {}
}
