import Foundation
import PIProviders
import Testing
@testable import PromptEval

/// Percentiles, pass rates and the gate verdict, on synthetic results.
struct StatisticsAndGateTests {
    static let balanced = EvalConfiguration.shipped(.balanced, provider: .anthropic)
    static let fast = EvalConfiguration.shipped(.fast, provider: .anthropic)

    /// A synthetic run: short fixtures by default, all checks passing, graded 5.
    static func record(
        _ fixtureID: String = "es-email",
        _ configuration: EvalConfiguration = balanced,
        repetition: Int = 1,
        checksPass: Bool = true,
        overall: Int? = 5,
        failing: Set<String> = [],
        firstText: Double = 1.0,
        total: Double = 3.0,
        complete: Bool = true
    ) -> RunRecord {
        let measurement = TurnMeasurement(
            timeToFirstEvent: firstText / 2,
            timeToFirstText: firstText,
            totalTime: total,
            outputCharacters: 200,
            usage: UsageRecord(inputTokens: 2_000, outputTokens: 300),
            finishReason: complete ? TurnMeasurement.complete : "truncated"
        )
        let checks = checksPass ? [CheckResult.pass("completed")] : [CheckResult.pass("completed"), .fail("length", "too long")]
        var judge: JudgeOutcome?
        if let overall {
            let criteria = Dictionary(uniqueKeysWithValues: RubricJudge.criteria.map {
                ($0, CriterionVerdict(passed: !failing.contains($0), reason: "r"))
            })
            judge = JudgeOutcome(primary: JudgeVerdict(provider: .anthropic, model: "claude-opus-5-5", criteria: criteria, overall: overall,
                                                       error: nil, usage: UsageRecord(inputTokens: 3_000, outputTokens: 500)),
                                 crossCheck: nil)
        }
        return RunRecord(fixtureID: fixtureID, configuration: configuration, repetition: repetition, draftID: "ab12",
                         turns: [TurnRecord(instruction: nil, measurement: measurement)], firstOutput: nil, output: "A prompt.",
                         checks: checks, judge: judge, startedAt: Date(timeIntervalSince1970: 0))
    }

    static func stats(_ records: [RunRecord], _ configuration: EvalConfiguration = balanced) -> ConfigurationStats {
        ConfigurationStats(configuration: configuration, records: records) { id in
            Shipped.fixtures.fixture(withID: id)?.isShort ?? false
        }
    }

    static func gate(_ records: [RunRecord], _ configuration: EvalConfiguration = balanced, checks: [ConfigurationCheck] = []) -> GateReport {
        ShipGate.evaluate(stats: [stats(records, configuration)], configurationChecks: checks)
    }

    /// Three clean repetitions of a few short fixtures.
    static func cleanRuns(_ configuration: EvalConfiguration = balanced, firstText: Double = 1.0, total: Double = 3.0) -> [RunRecord] {
        (1...3).flatMap { repetition in
            ["es-email", "en-casual", "es-question"].map { record($0, configuration, repetition: repetition, firstText: firstText, total: total) }
        }
    }

    // MARK: - Statistics

    @Test
    func percentilesInterpolate() throws {
        #expect(Statistics.percentile([1, 2, 3, 4], 0.5) == 2.5)
        #expect(abs(try #require(Statistics.percentile([1, 2, 3, 4], 0.9)) - 3.7) < 1e-9)
        #expect(Statistics.percentile([4, 1, 3, 2], 0) == 1)
        #expect(Statistics.percentile([4, 1, 3, 2], 1) == 4)
        #expect(Statistics.percentile([7], 0.9) == 7)
        #expect(Statistics.percentile([], 0.5) == nil)
        #expect(Statistics.mean([1, 2, 6]) == 3)
        #expect(Statistics.rate(1, of: 4) == 0.25)
        #expect(Statistics.rate(0, of: 0) == nil)
    }

    @Test
    func configurationStatsCountWhatTheGateNeeds() {
        let records = [
            Self.record("es-email", repetition: 1, overall: 5, firstText: 1, total: 2),
            Self.record("es-email", repetition: 2, checksPass: false, overall: 2, failing: ["nothing_lost"], firstText: 2, total: 4),
            Self.record("en-long-messy", repetition: 1, overall: 4, firstText: 3, total: 9),
            Self.record("es-email", Self.fast, repetition: 1),
        ]
        let stat = Self.stats(records)
        #expect(stat.runs == 3, "only this configuration's runs")
        #expect(stat.deterministicPassed == 2)
        #expect(stat.deterministicPassRate == 2.0 / 3.0)
        #expect(stat.failingChecks.map(\.fixtureID) == ["es-email"])
        #expect(stat.failingChecks.first?.repetition == 2)
        #expect(stat.judged == 3)
        #expect(stat.criterionRate("nothing_lost") == 2.0 / 3.0)
        #expect(stat.criterionRate("intent_preserved") == 1)
        #expect(stat.meanOverall == 11.0 / 3.0)
        #expect(stat.lowScoreRepetitions == ["es-email": 1])
        #expect(stat.firstText.sorted() == [1, 2, 3])
        #expect(stat.shortFirstText.sorted() == [1, 2], "en-long-messy is not short")
        #expect(stat.shortTotal.sorted() == [2, 4])
        let engineCost = 3 * (2_000 * 2.0 + 300 * 10.0) / 1_000_000
        #expect(abs((stat.engineCost ?? 0) - engineCost) < 1e-12)
    }

    @Test
    func crossCheckAgreement() {
        var record = Self.record()
        var cross = record.judge!.primary
        cross.provider = .openai
        cross.model = "gpt-6.2-sol"
        cross.criteria["proportionate"]?.passed = false
        cross.overall = 3
        record.judge?.crossCheck = cross
        let stat = Self.stats([record])
        #expect(stat.crossChecked == 1)
        #expect(stat.crossCriteriaAgreement == 7.0 / 8.0)
        #expect(stat.crossOverallWithinOne == 0)
    }

    // MARK: - Gate

    @Test
    func cleanRunsPass() {
        let report = Self.gate(Self.cleanRuns())
        #expect(report.verdict == .pass, "\(report.gates.flatMap(\.criteria).filter { $0.status != .pass })")
        #expect(report.exitStatus == 0)
        #expect(report.gates.count == 1)
        #expect(report.gates[0].tier == .balanced)
    }

    @Test
    func oneDeterministicFailureFails() {
        var runs = Self.cleanRuns()
        runs[4] = Self.record("en-casual", repetition: 2, checksPass: false)
        let report = Self.gate(runs)
        #expect(report.verdict == .fail)
        #expect(report.exitStatus == 1)
        #expect(report.gates[0].criteria.first { $0.name == "zero deterministic failures" }?.status == .fail)
    }

    @Test
    func aFailingConfigurationCheckFailsButAWarningDoesNot() {
        let failing = ConfigurationCheck(configurationID: Self.balanced.id, name: "cache_read", status: .fail, detail: "0 cached")
        #expect(Self.gate(Self.cleanRuns(), checks: [failing]).verdict == .fail)
        let warning = ConfigurationCheck(configurationID: Self.balanced.id, name: "cache_read", status: .warning, detail: "no usage")
        #expect(Self.gate(Self.cleanRuns(), checks: [warning]).verdict == .pass)
        let otherConfiguration = ConfigurationCheck(configurationID: Self.fast.id, name: "cache_read", status: .fail, detail: "0 cached")
        #expect(Self.gate(Self.cleanRuns(), checks: [otherConfiguration]).verdict == .pass)
    }

    @Test
    func anAnswerInsteadOfAPromptFailsEvenOnce() {
        var runs = Self.cleanRuns()
        runs[0] = Self.record("es-email", repetition: 1, overall: 4, failing: ["is_a_prompt_not_an_answer"])
        #expect(Self.gate(runs).verdict == .fail)
    }

    @Test
    func fidelityCriteriaNeedNinetyFivePercent() {
        // 1 miss in 9 is 89 %: below the bar.
        var runs = Self.cleanRuns()
        runs[3] = Self.record("es-email", repetition: 2, failing: ["nothing_invented"])
        let report = Self.gate(runs)
        #expect(report.verdict == .fail)
        #expect(report.gates[0].criteria.first { $0.name.hasPrefix("nothing_invented") }?.status == .fail)

        // 1 miss in 20 is 95 %: on the bar.
        let many = (1...20).map { Self.record("es-email", repetition: $0, failing: $0 == 1 ? ["nothing_lost"] : []) }
        #expect(Self.gate(many).verdict == .pass)
    }

    @Test
    func meanOverallThresholdDependsOnTheTier() {
        let scores = [4, 4, 4, 4, 3, 4, 4, 4, 3, 4] // mean 3.8
        let balancedRuns = scores.enumerated().map { Self.record("es-email", Self.balanced, repetition: $0.offset + 1, overall: $0.element) }
        let fastRuns = scores.enumerated().map { Self.record("es-email", Self.fast, repetition: $0.offset + 1, overall: $0.element) }
        #expect(Self.gate(balancedRuns).verdict == .fail)
        #expect(Self.gate(fastRuns, Self.fast).verdict == .pass)
    }

    @Test
    func aFixtureScoringLowTwiceFails() {
        var runs = Self.cleanRuns()
        runs = runs.filter { $0.fixtureID != "es-question" }
        runs += [Self.record("es-question", repetition: 1, overall: 2), Self.record("es-question", repetition: 2, overall: 5),
                 Self.record("es-question", repetition: 3, overall: 5)]
        runs += (4...12).map { Self.record("en-casual", repetition: $0) }
        #expect(Self.gate(runs).verdict == .pass, "one low repetition out of three is tolerated")
        runs[runs.firstIndex { $0.fixtureID == "es-question" && $0.repetition == 2 }!] = Self.record("es-question", repetition: 2, overall: 1)
        let report = Self.gate(runs)
        #expect(report.verdict == .fail)
        #expect(report.gates[0].criteria.first { $0.name.hasPrefix("no fixture") }?.detail == "es-question")
    }

    @Test
    func latencyTargetsAtTheMedianOfShortFixtures() {
        #expect(Self.gate(Self.cleanRuns(Self.fast, firstText: 1.4, total: 3.9), Self.fast).verdict == .pass)
        #expect(Self.gate(Self.cleanRuns(Self.fast, firstText: 1.6, total: 3.0), Self.fast).verdict == .fail)
        #expect(Self.gate(Self.cleanRuns(Self.fast, firstText: 1.0, total: 4.5), Self.fast).verdict == .fail)
        #expect(Self.gate(Self.cleanRuns(Self.balanced, firstText: 2.9, total: 7.9)).verdict == .pass)
        let quality = EvalConfiguration.shipped(.quality, provider: .openai)
        #expect(Self.gate(Self.cleanRuns(quality, firstText: 7.5, total: 19), quality).verdict == .pass)
        #expect(Self.gate(Self.cleanRuns(quality, firstText: 8.5, total: 19), quality).verdict == .fail)
    }

    @Test
    func withoutTheJudgeTheGateIsIncomplete() {
        let runs = (1...3).map { Self.record("es-email", repetition: $0, overall: nil) }
        let report = Self.gate(runs)
        #expect(report.verdict == .incomplete)
        #expect(report.exitStatus == 1)
        #expect(report.gates[0].criteria.contains { $0.status == .notEvaluated && $0.detail.contains("--judge") })
    }

    @Test
    func withoutShortFixturesLatencyIsNotEvaluated() {
        let runs = (1...3).map { Self.record("en-long-messy", repetition: $0) }
        #expect(Self.gate(runs).verdict == .incomplete)
    }

    @Test
    func aFailureBeatsMissingData() {
        let runs = (1...3).map { Self.record("es-email", repetition: $0, checksPass: $0 != 2, overall: nil) }
        #expect(Self.gate(runs).verdict == .fail)
    }

    @Test
    func onlyShippedPresetsAreGated() {
        let candidate = EvalConfiguration.candidate(.anthropic, "claude-opus-5-5", .low)
        #expect(candidate.preset == nil)
        let report = ShipGate.evaluate(stats: [Self.stats(Self.cleanRuns(candidate), candidate)], configurationChecks: [])
        #expect(report.gates.isEmpty)
        #expect(report.verdict == .incomplete)
    }

    @Test
    func tierFitUsesEachTiersThresholds() {
        let stat = Self.stats(Self.cleanRuns(Self.balanced, firstText: 2.0, total: 6.0))
        let fast = GateStatus.combined(ShipGate.criteria(stat, configurationChecks: [], tier: .fast).map(\.status))
        let balanced = GateStatus.combined(ShipGate.criteria(stat, configurationChecks: [], tier: .balanced).map(\.status))
        #expect(fast == .fail, "2 s to first text misses the fast target")
        #expect(balanced == .pass)
    }

    @Test
    func theSummaryShowsTheVerdictAndTheFailures() {
        var runs = Self.cleanRuns()
        runs[1] = Self.record("en-casual", repetition: 1, checksPass: false, overall: 2, failing: ["nothing_lost"])
        let stat = Self.stats(runs)
        let gate = ShipGate.evaluate(stats: [stat], configurationChecks: [], notes: ["A scope note."])
        let info = RunInfo(mode: "full", startedAt: Date(timeIntervalSince1970: 0), finishedAt: nil, repetitions: 3,
                           fixtureIDs: ["es-email", "en-casual", "es-question"], configurations: [Self.balanced],
                           judgeModel: "claude-opus-5-5 (medium)", crossCheckModel: nil)
        let markdown = SummaryWriter.markdown(SummaryInput(info: info, records: runs, configurationChecks: [], stats: [stat], gate: gate))
        #expect(markdown.contains("## Ship gate: FAIL"))
        #expect(markdown.contains("> A scope note."))
        #expect(markdown.contains("anthropic/balanced · en-casual #1 · length: too long"))
        #expect(markdown.contains("## Judge scores of 2 or less"))
        #expect(markdown.contains("| anthropic/balanced | claude-sonnet-5-5 · low | 9 | 89 % |"))
    }
}
