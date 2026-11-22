import Foundation
import PIPrompts
import PIProviders

/// What the runner talks to: the shipped prompt engine and one provider client per API.
/// Tests pass scripted providers; the tool passes `AnthropicProvider` and `OpenAIProvider`.
struct EvalEngine: Sendable {
    var library: TargetPackLibrary
    var composer: PromptComposer
    var providers: [ProviderID: any PromptEngineProvider]
    var keys: [ProviderID: APIKey]
}

/// Runs jobs against the engine, a few at a time, and checks and grades each result.
struct EvalRunner: Sendable {
    var engine: EvalEngine
    var judge: JudgeSetup?
    var concurrency: Int
    var now: @Sendable () -> Date = { Date() }

    /// Runs every job, at most `concurrency` at once, handing each record to `onRecord` as it
    /// completes (in completion order). Returns the records in job order.
    func run(_ jobs: [EvalJob], onRecord: @escaping @Sendable (RunRecord, _ completed: Int) async -> Void) async -> [RunRecord] {
        var records: [(index: Int, record: RunRecord)] = []
        records.reserveCapacity(jobs.count)
        await withTaskGroup(of: (Int, RunRecord).self) { group in
            var pending = jobs.makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let job = pending.next() else { break }
                group.addTask { (job.index, await self.run(job)) }
            }
            while let (index, record) = await group.next() {
                records.append((index, record))
                await onRecord(record, records.count)
                if let job = pending.next() {
                    group.addTask { (job.index, await self.run(job)) }
                }
            }
        }
        return records.sorted { $0.index < $1.index }.map(\.record)
    }

    /// One job: the first rewrite, the refinement when the fixture has one, the deterministic
    /// checks, and the judge when enabled.
    func run(_ job: EvalJob) async -> RunRecord {
        let fixture = job.fixture
        let configuration = job.configuration
        var record = RunRecord(
            fixtureID: fixture.id,
            configuration: configuration,
            repetition: job.repetition,
            draftID: "",
            turns: [],
            firstOutput: nil,
            output: "",
            checks: [],
            judge: nil,
            startedAt: now()
        )
        guard let target = engine.library.pack(withID: fixture.target) else {
            return failed(record, fixture: fixture, error: "unknownTarget(\(fixture.target))")
        }
        guard DraftLimits.validate(fixture.draft).isSubmittable else {
            return failed(record, fixture: fixture, error: "draftNotSubmittable")
        }
        guard let provider = engine.providers[configuration.provider], let key = engine.keys[configuration.provider] else {
            return failed(record, fixture: fixture, error: ErrorRecord.caseName(.missingKey(configuration.provider)))
        }

        let selection = configuration.selection()
        let preferences = fixture.promptPreferences
        var conversation = engine.composer.startConversation(draft: fixture.draft, target: target)
        record.draftID = conversation.draftID

        let first = await turn(conversation, target: target, preferences: preferences, selection: selection,
                               draft: fixture.draft, provider: provider, key: key)
        record.turns.append(TurnRecord(instruction: nil, measurement: first.measurement))
        record.output = first.shown

        if let instruction = fixture.refine, first.measurement.isComplete, !first.shown.isEmpty {
            // As in ImproveSession.refine(_:), the shown text goes back as the assistant turn.
            conversation.appendRevision(previousOutput: first.shown, instruction: instruction)
            let second = await turn(conversation, target: target, preferences: preferences, selection: selection,
                                    draft: fixture.draft, provider: provider, key: key)
            record.turns.append(TurnRecord(instruction: instruction, measurement: second.measurement))
            record.firstOutput = first.shown
            record.output = second.shown
        }

        record.checks = DeterministicChecks.run(CheckInput(fixture: fixture, record: record))
        if let judge, record.completionFailure == nil, !record.output.allSatisfy(\.isWhitespace) {
            record.judge = await grade(record, fixture: fixture, target: target, preferences: preferences, judge: judge)
        }
        return record
    }

    /// Sends the conversation's next request and post-processes the reply as the app does.
    private func turn(
        _ conversation: PromptConversation,
        target: TargetPack,
        preferences: PromptPreferences,
        selection: EngineSelection,
        draft: String,
        provider: any PromptEngineProvider,
        key: APIKey
    ) async -> (shown: String, measurement: TurnMeasurement) {
        let request = EvalRequestBuilder.request(for: conversation, target: target, preferences: preferences,
                                                 selection: selection, composer: engine.composer)
        let collected = await StreamCollector.collect(request, provider: provider, key: key)
        let processed = OutputPostProcessor.process(collected.rawText, draft: draft)
        var measurement = collected.measurement
        measurement.outputCharacters = processed.text.count
        measurement.unwrappedFence = processed.didUnwrapFence
        measurement.strippedPreface = processed.didStripPreface
        return (processed.text, measurement)
    }

    /// Grades the run's output with the primary judge and, when the run is in the sample, the
    /// cross-check.
    private func grade(_ record: RunRecord, fixture: Fixture, target: TargetPack, preferences: PromptPreferences, judge: JudgeSetup) async -> JudgeOutcome {
        let message = RubricJudge.userMessage(
            draft: fixture.draft,
            target: target,
            preferences: preferences,
            revision: record.turns.count > 1 ? fixture.refine : nil,
            output: record.output
        )
        let primary = await grade(with: judge.primary, message: message)
        var crossCheck: JudgeVerdict?
        if let model = judge.crossCheck,
           judge.crossChecks(fixtureID: record.fixtureID, configurationID: record.configuration.id, repetition: record.repetition) {
            crossCheck = await grade(with: model, message: message)
        }
        return JudgeOutcome(primary: primary, crossCheck: crossCheck)
    }

    /// One more attempt when the first verdict is unusable: an ungraded run leaves the gate
    /// incomplete, and the provider client has already retried transient errors.
    static let judgeAttempts = 2

    private func grade(with model: JudgeModel, message: String) async -> JudgeVerdict {
        guard let provider = engine.providers[model.provider], let key = engine.keys[model.provider] else {
            return JudgeVerdict(provider: model.provider, model: model.model, criteria: [:], overall: nil,
                                error: "no \(model.provider.displayName) key for the judge")
        }
        var verdict = await RubricJudge.grade(model: model, userMessage: message, provider: provider, key: key)
        for _ in 1..<Self.judgeAttempts where !verdict.isUsable {
            verdict = await RubricJudge.grade(model: model, userMessage: message, provider: provider, key: key)
        }
        return verdict
    }

    /// A run that could not be sent: one turn carrying `error`, which the checks report as not
    /// completed.
    private func failed(_ record: RunRecord, fixture: Fixture, error: String) -> RunRecord {
        var record = record
        record.turns = [TurnRecord(instruction: nil, measurement: TurnMeasurement(error: ErrorRecord(name: error)))]
        record.checks = DeterministicChecks.run(CheckInput(fixture: fixture, record: record))
        return record
    }

    // MARK: - Cache probe

    /// Sends the same request twice in a row and checks the second read from the cache.
    func probeCache(configuration: EvalConfiguration, fixture: Fixture) async -> ConfigurationCheck {
        guard let target = engine.library.pack(withID: fixture.target),
              let provider = engine.providers[configuration.provider], let key = engine.keys[configuration.provider]
        else {
            return ConfigurationCheck(configurationID: configuration.id, name: ConfigurationChecks.Name.cacheRead,
                                      status: .warning, detail: "cache probe not run (no key or unknown target)")
        }
        let conversation = engine.composer.startConversation(draft: fixture.draft, target: target)
        let request = EvalRequestBuilder.request(for: conversation, target: target, preferences: fixture.promptPreferences,
                                                 selection: configuration.selection(), composer: engine.composer)
        let first = await StreamCollector.collect(request, provider: provider, key: key)
        let second = await StreamCollector.collect(request, provider: provider, key: key)
        return ConfigurationChecks.cacheRead(configurationID: configuration.id, first: first.measurement, second: second.measurement)
    }

    /// Probes every configuration, `concurrency` at a time (each probe's two requests in order).
    func probeCaches(_ configurations: [EvalConfiguration], fixture: Fixture) async -> [ConfigurationCheck] {
        var checks: [(Int, ConfigurationCheck)] = []
        await withTaskGroup(of: (Int, ConfigurationCheck).self) { group in
            var pending = configurations.enumerated().makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let (index, configuration) = pending.next() else { break }
                group.addTask { (index, await self.probeCache(configuration: configuration, fixture: fixture)) }
            }
            while let result = await group.next() {
                checks.append(result)
                if let (index, configuration) = pending.next() {
                    group.addTask { (index, await self.probeCache(configuration: configuration, fixture: fixture)) }
                }
            }
        }
        return checks.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
