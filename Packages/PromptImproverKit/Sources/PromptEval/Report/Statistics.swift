import Foundation

/// Small, exact statistics helpers.
enum Statistics {
    /// The `p`-th percentile (0–1) with linear interpolation between closest ranks; nil for no values.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func rate(_ count: Int, of total: Int) -> Double? {
        total == 0 ? nil : Double(count) / Double(total)
    }
}

/// A failing deterministic check, located.
struct FailingCheck: Sendable, Hashable {
    var fixtureID: String
    var repetition: Int
    var check: CheckResult
}

/// Everything the summary and the gate need about one configuration's runs.
struct ConfigurationStats: Sendable {
    var configuration: EvalConfiguration
    var runs: Int
    var deterministicPassed: Int
    var failingChecks: [FailingCheck]
    /// Every request's time to first text and total time.
    var firstText: [Double]
    var total: [Double]
    /// First requests of short fixtures only: what the latency targets are measured on.
    var shortFirstText: [Double]
    var shortTotal: [Double]
    /// Completed runs (the ones the judge grades).
    var judgeEligible: Int
    /// Runs with a usable primary verdict.
    var judged: Int
    var criterionPasses: [String: Int]
    var overallScores: [Int]
    /// Per fixture, how many repetitions scored 2 or less.
    var lowScoreRepetitions: [String: Int]
    var judgeErrors: [String]
    /// Runs graded by both judges, and how often they agreed.
    var crossChecked: Int
    var crossCriteriaAgreement: Double?
    var crossOverallWithinOne: Double?
    var retries: Int
    var engineCost: Double?
    var judgeCost: Double?

    var deterministicPassRate: Double? { Statistics.rate(deterministicPassed, of: runs) }

    func criterionRate(_ name: String) -> Double? {
        Statistics.rate(criterionPasses[name] ?? 0, of: judged)
    }

    var meanOverall: Double? { Statistics.mean(overallScores.map(Double.init)) }

    /// - Parameter isShort: whether a fixture id names a short fixture.
    init(configuration: EvalConfiguration, records: [RunRecord], isShort: (String) -> Bool) {
        self.configuration = configuration
        let records = records.filter { $0.configuration.id == configuration.id }
        runs = records.count
        deterministicPassed = records.count(where: \.deterministicPassed)
        failingChecks = records.flatMap { record in
            record.failedChecks.map { FailingCheck(fixtureID: record.fixtureID, repetition: record.repetition, check: $0) }
        }
        let measurements = records.flatMap { $0.turns.map(\.measurement) }
        firstText = measurements.compactMap(\.timeToFirstText)
        total = measurements.filter(\.isComplete).map(\.totalTime)
        let shortFirstTurns = records.filter { isShort($0.fixtureID) }.compactMap { $0.turns.first?.measurement }
        shortFirstText = shortFirstTurns.compactMap(\.timeToFirstText)
        shortTotal = shortFirstTurns.filter(\.isComplete).map(\.totalTime)
        retries = measurements.reduce(0) { $0 + $1.retries }

        let eligible = records.filter { $0.completionFailure == nil && !$0.output.allSatisfy(\.isWhitespace) }
        judgeEligible = eligible.count
        let verdicts = records.compactMap(\.judge?.primary).filter(\.isUsable)
        judged = verdicts.count
        var passes: [String: Int] = [:]
        for verdict in verdicts {
            for (name, criterion) in verdict.criteria where criterion.passed {
                passes[name, default: 0] += 1
            }
        }
        criterionPasses = passes
        overallScores = verdicts.compactMap(\.overall)
        var low: [String: Int] = [:]
        for record in records {
            if let overall = record.judge?.primary.overall, overall <= 2 {
                low[record.fixtureID, default: 0] += 1
            }
        }
        lowScoreRepetitions = low
        judgeErrors = records.compactMap { record in
            record.judge.flatMap { $0.primary.error.map { "\(record.fixtureID) #\(record.repetition): \($0)" } }
        }

        var compared = 0
        var criteriaAgreed = 0
        var criteriaCompared = 0
        var overallAgreed = 0
        for record in records {
            guard let outcome = record.judge, let cross = outcome.crossCheck, outcome.primary.isUsable, cross.isUsable else { continue }
            compared += 1
            for (name, criterion) in outcome.primary.criteria {
                guard let other = cross.criteria[name] else { continue }
                criteriaCompared += 1
                if other.passed == criterion.passed { criteriaAgreed += 1 }
            }
            if let a = outcome.primary.overall, let b = cross.overall, abs(a - b) <= 1 { overallAgreed += 1 }
        }
        crossChecked = compared
        crossCriteriaAgreement = Statistics.rate(criteriaAgreed, of: criteriaCompared)
        crossOverallWithinOne = Statistics.rate(overallAgreed, of: compared)

        engineCost = Self.sum(records.flatMap(\.turns).compactMap { turn in
            turn.measurement.usage.flatMap {
                CostEstimator.actualCost(model: configuration.model, provider: configuration.provider, usage: $0)
            }
        })
        judgeCost = Self.sum(records.compactMap(\.judge).flatMap { outcome in
            [outcome.primary, outcome.crossCheck].compactMap { verdict -> Double? in
                guard let verdict, let usage = verdict.usage else { return nil }
                return CostEstimator.actualCost(model: verdict.model, provider: verdict.provider, usage: usage)
            }
        })
    }

    private static func sum(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }
}
