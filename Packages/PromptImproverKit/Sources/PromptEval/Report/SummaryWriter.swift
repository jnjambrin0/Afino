import Foundation

/// Everything `summary.md` is written from.
struct SummaryInput: Sendable {
    var info: RunInfo
    var records: [RunRecord]
    var configurationChecks: [ConfigurationCheck]
    var stats: [ConfigurationStats]
    var gate: GateReport
}

/// Renders `summary.md`.
enum SummaryWriter {
    static func markdown(_ input: SummaryInput) -> String {
        var out: [String] = []
        let info = input.info
        out.append("# prompt-eval: \(info.mode)")
        out.append("")
        var facts = [
            "Started \(timestamp(info.startedAt))",
            "\(info.fixtureIDs.count) fixtures",
            "\(info.configurations.count) configurations",
            "\(info.repetitions) repetition\(info.repetitions == 1 ? "" : "s")",
            "\(input.records.count) runs",
        ]
        if let judge = info.judgeModel {
            facts.append("judge \(judge)" + (info.crossCheckModel.map { ", cross-checked by \($0) on a 20 % sample" } ?? ""))
        } else {
            facts.append("no judge")
        }
        out.append(facts.joined(separator: " · "))
        out.append("")

        out += gateSection(input.gate)
        out += configurationTable(input.stats)
        out += judgeTable(input.stats)
        out += configurationChecksTable(input.configurationChecks, configurations: info.configurations)
        if info.mode == EvalMode.sweep.rawValue {
            out += tierFitTable(input.stats, configurationChecks: input.configurationChecks)
        }
        out += failingChecks(input.stats)
        out += lowScores(input.records)
        out += judgeErrors(input.stats)
        out.append("Latency is measured from handing the request to the provider client: first text = first text delta, total = end of the answer. \"Short\" fixtures have drafts of at most \(Fixture.shortDraftCharacters) characters; the gate reads their first requests. Costs are approximate, from reported usage and the built-in price table.")
        out.append("")
        return out.joined(separator: "\n")
    }

    // MARK: - Sections

    static func gateSection(_ gate: GateReport) -> [String] {
        var out = ["## Ship gate: \(gate.verdict.rawValue)", ""]
        for note in gate.notes {
            out.append("> \(note)")
        }
        if !gate.notes.isEmpty { out.append("") }
        guard !gate.gates.isEmpty else { return out }
        out.append("| Configuration | Preset | Result | Failing or missing |")
        out.append("|---|---|---|---|")
        for configurationGate in gate.gates {
            let open = configurationGate.criteria.filter { $0.status != .pass }.map(\.name)
            out.append("| \(configurationGate.configuration.id) | \(configurationGate.tier.rawValue) | \(configurationGate.status.label) | \(open.isEmpty ? "—" : open.joined(separator: "; ")) |")
        }
        out.append("")
        for configurationGate in gate.gates {
            out.append("### \(configurationGate.configuration.id) (\(configurationGate.configuration.label))")
            out.append("")
            for criterion in configurationGate.criteria {
                out.append("- \(criterion.status.label): \(criterion.name) — \(criterion.detail)")
            }
            out.append("")
        }
        return out
    }

    static func configurationTable(_ stats: [ConfigurationStats]) -> [String] {
        var out = ["## Configurations", ""]
        out.append("| Configuration | Model | Runs | Deterministic pass | Judge mean | First text p50 / p90 | Total p50 / p90 | Short p50 first / total | Retries | Cost (engine + judge) |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for stat in stats {
            let cost = [stat.engineCost, stat.judgeCost].compactMap(\.self)
            out.append("| \(stat.configuration.id) | \(stat.configuration.label) | \(stat.runs) | \(rate(stat.deterministicPassRate)) | \(number(stat.meanOverall)) | \(seconds(stat.firstText, 0.5)) / \(seconds(stat.firstText, 0.9)) | \(seconds(stat.total, 0.5)) / \(seconds(stat.total, 0.9)) | \(seconds(stat.shortFirstText, 0.5)) / \(seconds(stat.shortTotal, 0.5)) | \(stat.retries) | \(cost.isEmpty ? "n/a" : CostEstimator.format(cost.reduce(0, +))) |")
        }
        out.append("")
        return out
    }

    static func judgeTable(_ stats: [ConfigurationStats]) -> [String] {
        guard stats.contains(where: { $0.judged > 0 }) else { return [] }
        var out = ["## Judge", ""]
        let header = RubricJudge.criteria.map { $0.replacingOccurrences(of: "_", with: " ") }
        out.append("| Configuration | Graded | " + header.joined(separator: " | ") + " | Mean overall | Cross-check agreement |")
        out.append("|---|---|" + String(repeating: "---|", count: header.count) + "---|---|")
        for stat in stats {
            let rates = RubricJudge.criteria.map { stat.judged > 0 ? rate(stat.criterionRate($0)) : "—" }
            var agreement = "—"
            if stat.crossChecked > 0 {
                agreement = "\(stat.crossChecked) runs: criteria \(rate(stat.crossCriteriaAgreement)), overall ±1 \(rate(stat.crossOverallWithinOne))"
            }
            out.append("| \(stat.configuration.id) | \(stat.judged)/\(stat.judgeEligible) | " + rates.joined(separator: " | ") + " | \(number(stat.meanOverall)) | \(agreement) |")
        }
        out.append("")
        return out
    }

    static func configurationChecksTable(_ checks: [ConfigurationCheck], configurations: [EvalConfiguration]) -> [String] {
        guard !checks.isEmpty else { return [] }
        var out = ["## Configuration checks", ""]
        out.append("| Configuration | Check | Result | Detail |")
        out.append("|---|---|---|---|")
        let order = Dictionary(uniqueKeysWithValues: configurations.enumerated().map { ($1.id, $0) })
        for check in checks.sorted(by: { (order[$0.configurationID] ?? 0, $0.name) < (order[$1.configurationID] ?? 0, $1.name) }) {
            let status = switch check.status {
            case .pass: "pass"
            case .fail: "FAIL"
            case .warning: "warning"
            }
            out.append("| \(check.configurationID) | \(check.name) | \(status) | \(check.detail) |")
        }
        out.append("")
        return out
    }

    /// Sweep only: which tier's gate each candidate would meet.
    static func tierFitTable(_ stats: [ConfigurationStats], configurationChecks: [ConfigurationCheck]) -> [String] {
        var out = ["## Sweep: which tier each candidate fits", ""]
        out.append("A candidate fits a tier when it meets that tier's whole gate (quality bars and latency targets). Pick, per provider and tier, the cheapest candidate that fits.")
        out.append("")
        out.append("| Candidate | Same as preset | Fast | Balanced | Quality | Mean overall | Short p50 first / total | Cost per run |")
        out.append("|---|---|---|---|---|---|---|---|")
        for stat in stats {
            let fits = PresetTier.allCases.map { tier in
                GateStatus.combined(ShipGate.criteria(stat, configurationChecks: configurationChecks, tier: tier).map(\.status)).label
            }
            let perRun = stat.engineCost.map { $0 / Double(max(1, stat.runs)) }
            out.append("| \(stat.configuration.id) | \(stat.configuration.preset?.rawValue ?? "—") | \(fits.joined(separator: " | ")) | \(number(stat.meanOverall)) | \(seconds(stat.shortFirstText, 0.5)) / \(seconds(stat.shortTotal, 0.5)) | \(perRun.map { String(format: "$%.4f", $0) } ?? "n/a") |")
        }
        out.append("")
        return out
    }

    static func failingChecks(_ stats: [ConfigurationStats]) -> [String] {
        let failing = stats.flatMap { stat in stat.failingChecks.map { (stat.configuration.id, $0) } }
        guard !failing.isEmpty else { return ["## Failing checks", "", "None.", ""] }
        var out = ["## Failing checks", ""]
        for (configurationID, failure) in failing {
            out.append("- \(configurationID) · \(failure.fixtureID) #\(failure.repetition) · \(failure.check.name): \(failure.check.detail)")
        }
        out.append("")
        return out
    }

    static func lowScores(_ records: [RunRecord]) -> [String] {
        let low = records.filter { ($0.judge?.primary.overall ?? 5) <= ShipGate.lowScore }
        guard !low.isEmpty else { return [] }
        var out = ["## Judge scores of 2 or less", ""]
        for record in low {
            let failed = record.judge?.primary.criteria.filter { !$0.value.passed }
                .sorted { $0.key < $1.key }
                .map { "\($0.key) (\($0.value.reason))" } ?? []
            out.append("- \(record.configuration.id) · \(record.fixtureID) #\(record.repetition) · \(record.judge?.primary.overall ?? 0): \(failed.joined(separator: "; "))")
        }
        out.append("")
        return out
    }

    static func judgeErrors(_ stats: [ConfigurationStats]) -> [String] {
        let errors = stats.flatMap { stat in stat.judgeErrors.map { "\(stat.configuration.id) · \($0)" } }
        guard !errors.isEmpty else { return [] }
        return ["## Judge failures (recorded, not fatal)", ""] + errors.map { "- \($0)" } + [""]
    }

    // MARK: - Formatting

    static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.0f %%", $0 * 100) } ?? "—"
    }

    static func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }

    static func seconds(_ values: [Double], _ p: Double) -> String {
        Statistics.percentile(values, p).map { String(format: "%.2f s", $0) } ?? "—"
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)) + " UTC"
    }
}
