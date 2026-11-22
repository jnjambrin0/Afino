import Foundation
import PIPrompts
import PIProviders

/// What the tool was asked to do.
enum EvalMode: String, Sendable, CaseIterable, Codable {
    case smoke
    case full
    case sweep
    case list
    case check

    var defaultRepetitions: Int {
        switch self {
        case .smoke: 1
        case .full, .sweep: 3
        case .list, .check: 1
        }
    }

    /// Smoke is a cheap health check; the modes that decide something grade with the judge.
    var judgesByDefault: Bool {
        switch self {
        case .full, .sweep: true
        case .smoke, .list, .check: false
        }
    }
}

/// One run to perform: a fixture on a configuration, for one repetition.
struct EvalJob: Sendable, Hashable {
    /// The job's position in the plan; the runner returns records in this order.
    var index: Int
    var fixture: Fixture
    var configuration: EvalConfiguration
    var repetition: Int
}

/// Everything a network mode will do, decided before anything is sent.
struct EvalPlan: Sendable {
    var mode: EvalMode
    var fixtures: [Fixture]
    var configurations: [EvalConfiguration]
    var repetitions: Int
    var judge: JudgeSetup?
    var jobs: [EvalJob]
    /// The fixture each configuration's cache probe sends twice: the shortest draft, so the probe
    /// costs little.
    var cacheProbeFixture: Fixture?

    /// The plan for `mode` over the providers that have a key.
    static func make(
        mode: EvalMode,
        providers: [ProviderID],
        library: FixtureLibrary,
        fixtureIDs: [String]?,
        repetitions: Int?,
        judge: Bool?
    ) throws(EvalError) -> EvalPlan {
        let fixtures: [Fixture]
        if let fixtureIDs {
            fixtures = try library.select(fixtureIDs)
        } else {
            fixtures = mode == .smoke ? library.smoke : library.fixtures
        }
        let configurations: [EvalConfiguration] = providers.flatMap { provider -> [EvalConfiguration] in
            switch mode {
            case .smoke: [.shipped(.balanced, provider: provider)]
            case .full: EvalConfiguration.shippedPresets(for: provider)
            case .sweep: EvalConfiguration.sweepCandidates(for: provider)
            case .list, .check: []
            }
        }
        let repetitions = max(1, repetitions ?? mode.defaultRepetitions)
        let judgeSetup = (judge ?? mode.judgesByDefault) ? JudgeSetup.make(availableProviders: Set(providers)) : nil
        return EvalPlan(
            mode: mode,
            fixtures: fixtures,
            configurations: configurations,
            repetitions: repetitions,
            judge: judgeSetup,
            jobs: interleavedJobs(fixtures: fixtures, configurations: configurations, repetitions: repetitions),
            cacheProbeFixture: fixtures.min { $0.draft.count < $1.draft.count }
        )
    }

    /// Repetition, then fixture, then configuration: every configuration's runs are spread over the
    /// whole session, so a slow or degraded period of an API affects all of them alike.
    static func interleavedJobs(fixtures: [Fixture], configurations: [EvalConfiguration], repetitions: Int) -> [EvalJob] {
        var jobs: [EvalJob] = []
        jobs.reserveCapacity(fixtures.count * configurations.count * repetitions)
        for repetition in 1...max(1, repetitions) {
            for fixture in fixtures {
                for configuration in configurations {
                    jobs.append(EvalJob(index: jobs.count, fixture: fixture, configuration: configuration, repetition: repetition))
                }
            }
        }
        return jobs
    }

    /// Engine requests (refinements send two), excluding cache probes and the judge.
    var engineRequestCount: Int {
        jobs.reduce(0) { $0 + $1.fixture.requestCount }
    }

    /// Cross-checked runs, from the judge's stable sample.
    var crossCheckCount: Int {
        guard let judge, judge.crossCheck != nil else { return 0 }
        return jobs.count { judge.crossChecks(fixtureID: $0.fixture.id, configurationID: $0.configuration.id, repetition: $0.repetition) }
    }

    /// Every request the plan sends, with estimated tokens.
    func requestEstimates(library: TargetPackLibrary, composer: PromptComposer) -> [RequestEstimate] {
        var estimates: [RequestEstimate] = []
        for job in jobs {
            guard let target = library.pack(withID: job.fixture.target) else { continue }
            let engine = Self.engineEstimates(fixture: job.fixture, configuration: job.configuration, target: target, composer: composer)
            estimates += engine
            guard let judge else { continue }
            let judged = judgeEstimate(model: judge.primary, fixture: job.fixture, target: target, outputTokens: engine.last?.outputTokens ?? 0)
            estimates.append(judged)
            if let crossCheck = judge.crossCheck,
               judge.crossChecks(fixtureID: job.fixture.id, configurationID: job.configuration.id, repetition: job.repetition) {
                estimates.append(judgeEstimate(model: crossCheck, fixture: job.fixture, target: target, outputTokens: engine.last?.outputTokens ?? 0))
            }
        }
        if let probe = cacheProbeFixture, let target = library.pack(withID: probe.target) {
            for configuration in configurations {
                let first = Self.engineEstimates(fixture: probe, configuration: configuration, target: target, composer: composer)[0]
                estimates += [first, first]
            }
        }
        return estimates
    }

    /// The first request and, for a refinement, the second.
    static func engineEstimates(fixture: Fixture, configuration: EvalConfiguration, target: TargetPack, composer: PromptComposer) -> [RequestEstimate] {
        let system = composer.systemBlocks(for: target, preferences: fixture.promptPreferences).joined(separator: "\n\n").count
        let run = composer.startConversation(draft: fixture.draft, target: target).runMessage.count
        let visible = CostEstimator.estimatedOutputTokens(forDraft: fixture.draft)
        let reasoning = CostEstimator.reasoningAllowance(effort: configuration.effort, thinkingDisabled: configuration.thinkingDisabled)
        let first = RequestEstimate(
            model: configuration.model,
            inputTokens: CostEstimator.estimatedTokens(characters: system + run),
            outputTokens: visible + reasoning
        )
        guard let refine = fixture.refine else { return [first] }
        // The second request adds the first output as input and wraps the revision request in
        // about 120 characters of tags and instruction.
        let revisionOverhead = 120 + refine.count
        let second = RequestEstimate(
            model: configuration.model,
            inputTokens: CostEstimator.estimatedTokens(characters: system + run + revisionOverhead) + visible,
            outputTokens: visible + reasoning
        )
        return [first, second]
    }

    /// One judge request: the rubric, the guidance, the draft, the output being graded and about
    /// 400 characters of tags; the reply, a JSON verdict with a reason per criterion, is about 400
    /// tokens.
    private func judgeEstimate(model: JudgeModel, fixture: Fixture, target: TargetPack, outputTokens: Int) -> RequestEstimate {
        let characters = RubricJudge.systemPrompt.count + target.guidance.count + fixture.draft.count + 400
        return RequestEstimate(
            model: model.model,
            inputTokens: CostEstimator.estimatedTokens(characters: characters) + outputTokens,
            outputTokens: 400 + CostEstimator.reasoningAllowance(effort: model.effort, thinkingDisabled: false),
            isJudge: true
        )
    }
}
