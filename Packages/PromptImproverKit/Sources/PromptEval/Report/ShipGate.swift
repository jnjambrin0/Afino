import Foundation

/// The outcome of one gate criterion.
enum GateStatus: String, Sendable, Hashable, Codable {
    case pass
    case fail
    /// No data to decide (no judge, no short fixture, no runs).
    case notEvaluated

    var label: String {
        switch self {
        case .pass: "pass"
        case .fail: "FAIL"
        case .notEvaluated: "not evaluated"
        }
    }

    /// Fail beats not evaluated beats pass.
    static func combined(_ statuses: [GateStatus]) -> GateStatus {
        if statuses.contains(.fail) { return .fail }
        if statuses.contains(.notEvaluated) || statuses.isEmpty { return .notEvaluated }
        return .pass
    }
}

/// One line of a configuration's gate, such as "nothing_lost ≥ 95 %", with its measured value.
struct GateCriterion: Sendable, Hashable {
    var name: String
    var status: GateStatus
    var detail: String
}

/// One configuration held to one tier's thresholds.
struct ConfigurationGate: Sendable {
    var configuration: EvalConfiguration
    var tier: PresetTier
    var criteria: [GateCriterion]

    var status: GateStatus { GateStatus.combined(criteria.map(\.status)) }
}

/// The run's verdict: PASS only when every gated configuration passes every criterion.
enum GateVerdict: String, Sendable, Hashable {
    case pass = "PASS"
    case fail = "FAIL"
    /// Nothing failed, but some criterion had no data, or no shipped preset was run.
    case incomplete = "INCOMPLETE"
}

/// The gate for every shipped preset in a run, its verdict and the notes on the run's scope.
struct GateReport: Sendable {
    var gates: [ConfigurationGate]
    var verdict: GateVerdict
    var notes: [String]

    /// 0 only when the gate passes.
    var exitStatus: Int32 { verdict == .pass ? 0 : 1 }
}

/// The ship gate: whether the shipped presets are good enough to release.
///
/// For every configuration that is a shipped preset: zero deterministic failures across all
/// repetitions (configuration checks included); the judge's `is_a_prompt_not_an_answer` at 100 %;
/// `intent_preserved`, `nothing_invented` and `nothing_lost` each at 95 % or more; a mean overall
/// score of 4.0 (3.7 for fast); no fixture scoring 2 or less in more than one repetition; and the
/// tier's latency targets at p50 on short fixtures.
enum ShipGate {
    static let mustAlwaysPass = "is_a_prompt_not_an_answer"
    static let highBarCriteria = ["intent_preserved", "nothing_invented", "nothing_lost"]
    static let highBarRate = 0.95
    static let lowScore = 2
    static let maxLowScoreRepetitions = 1

    /// The gate for every shipped preset in `stats`.
    static func evaluate(stats: [ConfigurationStats], configurationChecks: [ConfigurationCheck], notes: [String] = []) -> GateReport {
        let gates = stats.compactMap { stat -> ConfigurationGate? in
            guard let tier = stat.configuration.preset else { return nil }
            return ConfigurationGate(configuration: stat.configuration, tier: tier,
                                     criteria: criteria(stat, configurationChecks: configurationChecks, tier: tier))
        }
        var notes = notes
        let verdict: GateVerdict
        if gates.isEmpty {
            notes.append("No shipped preset was run, so there is nothing to gate.")
            verdict = .incomplete
        } else {
            switch GateStatus.combined(gates.map(\.status)) {
            case .pass: verdict = .pass
            case .fail: verdict = .fail
            case .notEvaluated: verdict = .incomplete
            }
        }
        return GateReport(gates: gates, verdict: verdict, notes: notes)
    }

    /// `stat` held to `tier`'s thresholds (also used to see which tiers a sweep candidate fits).
    static func criteria(_ stat: ConfigurationStats, configurationChecks: [ConfigurationCheck], tier: PresetTier) -> [GateCriterion] {
        var criteria: [GateCriterion] = []
        criteria.append(deterministic(stat, configurationChecks: configurationChecks))
        criteria += judge(stat, tier: tier)
        criteria += latency(stat, tier: tier)
        return criteria
    }

    static func deterministic(_ stat: ConfigurationStats, configurationChecks: [ConfigurationCheck]) -> GateCriterion {
        let name = "zero deterministic failures"
        guard stat.runs > 0 else { return GateCriterion(name: name, status: .notEvaluated, detail: "no runs") }
        let failingRuns = stat.runs - stat.deterministicPassed
        let failingConfig = configurationChecks.filter { $0.configurationID == stat.configuration.id && $0.status == .fail }
        var problems: [String] = []
        if failingRuns > 0 { problems.append("\(failingRuns) of \(stat.runs) runs failed a check") }
        problems += failingConfig.map { "\($0.name) failed" }
        return problems.isEmpty
            ? GateCriterion(name: name, status: .pass, detail: "\(stat.runs) runs, all checks passed")
            : GateCriterion(name: name, status: .fail, detail: problems.joined(separator: "; "))
    }

    static func judge(_ stat: ConfigurationStats, tier: PresetTier) -> [GateCriterion] {
        guard stat.judged > 0 else {
            let reason = stat.judgeEligible == 0 ? "no completed runs to grade" : "the judge did not run (use --judge)"
            let names = ["judge coverage", "\(mustAlwaysPass) = 100 %"] + highBarCriteria.map { "\($0) ≥ 95 %" }
                + [String(format: "mean overall ≥ %.1f", tier.minimumMeanOverall), "no fixture ≤ 2 in more than one repetition"]
            return names.map { GateCriterion(name: $0, status: .notEvaluated, detail: reason) }
        }
        var criteria: [GateCriterion] = []
        let coverage = "\(stat.judged) of \(stat.judgeEligible) completed runs graded"
        criteria.append(GateCriterion(name: "judge coverage", status: stat.judged >= stat.judgeEligible ? .pass : .notEvaluated, detail: coverage))

        let alwaysRate = stat.criterionRate(mustAlwaysPass) ?? 0
        criteria.append(GateCriterion(name: "\(mustAlwaysPass) = 100 %", status: alwaysRate >= 1 ? .pass : .fail, detail: percent(alwaysRate)))
        for name in highBarCriteria {
            let rate = stat.criterionRate(name) ?? 0
            criteria.append(GateCriterion(name: "\(name) ≥ 95 %", status: rate >= highBarRate ? .pass : .fail, detail: percent(rate)))
        }
        let mean = stat.meanOverall ?? 0
        criteria.append(GateCriterion(
            name: String(format: "mean overall ≥ %.1f", tier.minimumMeanOverall),
            status: mean >= tier.minimumMeanOverall ? .pass : .fail,
            detail: String(format: "%.2f over %d grades", mean, stat.overallScores.count)
        ))
        let repeatedLow = stat.lowScoreRepetitions.filter { $0.value > maxLowScoreRepetitions }.keys.sorted()
        criteria.append(GateCriterion(
            name: "no fixture ≤ 2 in more than one repetition",
            status: repeatedLow.isEmpty ? .pass : .fail,
            detail: repeatedLow.isEmpty ? "none" : repeatedLow.joined(separator: ", ")
        ))
        return criteria
    }

    static func latency(_ stat: ConfigurationStats, tier: PresetTier) -> [GateCriterion] {
        let target = tier.latencyTarget
        func criterion(_ name: String, _ values: [Double], limit: Double) -> GateCriterion {
            guard let p50 = Statistics.percentile(values, 0.5) else {
                return GateCriterion(name: name, status: .notEvaluated, detail: "no short fixture completed")
            }
            return GateCriterion(name: name, status: p50 <= limit ? .pass : .fail,
                                 detail: String(format: "p50 %.2f s over %d requests", p50, values.count))
        }
        return [
            criterion(String(format: "short fixtures: p50 first text ≤ %g s", target.firstText), stat.shortFirstText, limit: target.firstText),
            criterion(String(format: "short fixtures: p50 total ≤ %g s", target.total), stat.shortTotal, limit: target.total),
        ]
    }

    static func percent(_ rate: Double) -> String {
        String(format: "%.1f %%", rate * 100)
    }
}
