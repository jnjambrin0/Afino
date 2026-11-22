import Foundation

/// Everything a deterministic check looks at for one run.
struct CheckInput: Sendable {
    var fixture: Fixture
    /// The shown output of the last turn (post-processed, as the app shows it).
    var output: String
    /// Refinements: the shown output of the first turn.
    var previousOutput: String?
    /// Why the run did not complete, or nil when it did.
    var completionFailure: String?
    /// The run's `<draft>` id.
    var draftID: String

    init(fixture: Fixture, output: String, previousOutput: String? = nil, completionFailure: String? = nil, draftID: String) {
        self.fixture = fixture
        self.output = output
        self.previousOutput = previousOutput
        self.completionFailure = completionFailure
        self.draftID = draftID
    }

    init(fixture: Fixture, record: RunRecord) {
        self.init(
            fixture: fixture,
            output: record.output,
            previousOutput: record.firstOutput,
            completionFailure: record.completionFailure,
            draftID: record.draftID
        )
    }
}

/// Text that must never reach an output: the engine's own markup and phrases from its system prompt.
enum LeakMarkers {
    /// Distinctive sentences from `core.txt`. The schema tests check they really occur there.
    static let canaries = [
        "You are the rewriting engine inside Afino",
        "a prompt that quietly makes them is putting words in their mouth",
        "starting with its first word and ending with its last",
    ]

    /// The composer's tags and section names.
    static let markup = ["<draft", "</draft id", "target_guidance", "user_preferences", "revision_request"]
}

/// The deterministic checks: pure functions from a run to `[CheckResult]`.
///
/// Generic checks run on every fixture; the rest only when the fixture asks for them. A run that
/// did not complete gets the single failing `completed` check, since the rest would only repeat it.
enum DeterministicChecks {
    /// Check names as `results.jsonl` and the summary show them.
    enum Name {
        static let completed = "completed"
        static let noPrefaceOrCommentary = "no_preface_or_commentary"
        static let noWrappingFence = "no_wrapping_fence"
        static let preservedVerbatim = "preserved_verbatim"
        static let noInventedVariables = "no_invented_variables"
        static let mustContain = "must_contain"
        static let mustNotContain = "must_not_contain"
        static let mustMatch = "must_match"
        static let mustNotMatch = "must_not_match"
        static let language = "language"
        static let length = "length"
        static let codeFences = "code_fences"
        static let noLeakage = "no_leakage"
        static let fillIn = "fill_in"
        static let listItems = "list_items"
        static let similarity = "similarity"
    }

    /// Every check that applies to the run, in a fixed order.
    static func run(_ input: CheckInput) -> [CheckResult] {
        if let failure = input.completionFailure {
            return [.fail(Name.completed, failure)]
        }
        guard !input.output.allSatisfy(\.isWhitespace) else {
            return [.fail(Name.completed, "the output is empty")]
        }
        let fixture = input.fixture
        let output = input.output
        var results: [CheckResult] = [.pass(Name.completed, "\(TextAnalysis.wordCount(output)) words")]
        results.append(prefaceOrCommentary(output, draft: fixture.draft))
        results.append(wrappingFence(output, draft: fixture.draft))
        if !fixture.preserveVerbatim.isEmpty {
            results.append(preservedVerbatim(output, required: fixture.preserveVerbatim))
        }
        results.append(inventedVariables(output, draft: fixture.draft))
        if !fixture.mustContain.isEmpty {
            results.append(mustContain(output, fixture.mustContain))
        }
        if !fixture.mustNotContain.isEmpty {
            results.append(mustNotContain(output, fixture.mustNotContain))
        }
        if !fixture.mustMatch.isEmpty {
            results.append(mustMatch(output, fixture.mustMatch))
        }
        if !fixture.mustNotMatch.isEmpty {
            results.append(mustNotMatch(output, fixture.mustNotMatch))
        }
        if let language = language(output, expected: fixture.expectedLanguage) {
            results.append(language)
        }
        if let rule = fixture.length, !rule.isEmpty {
            results.append(length(output, rule: rule, draft: fixture.draft, previous: input.previousOutput))
        }
        results.append(codeFences(output, allowed: fixture.codeFencesAllowed, exactly: fixture.codeBlocks))
        results.append(leakage(output, draft: fixture.draft, draftID: input.draftID))
        if fixture.expectFillIn {
            results.append(fillIn(output))
        }
        if let maximum = fixture.maxListItems {
            results.append(listItems(output, maximum: maximum))
        }
        if let minimum = fixture.minSimilarityToDraft {
            results.append(similarity(output, draft: fixture.draft, minimum: minimum))
        }
        return results
    }

    // MARK: - Preface and closing commentary

    /// Openings that are chat, not prompt, when followed by punctuation ("Sure!", "Claro,").
    static let chattyOpenings = ["sure", "certainly", "of course", "absolutely", "claro", "por supuesto", "¡claro", "¡por supuesto", "desde luego"]
    /// Openings that introduce the result ("Here's the improved prompt").
    static let presentingOpenings = ["here's", "here’s", "here is", "aquí tienes", "aquí está", "aqui tienes", "aqui esta"]
    /// Words that make a presenting opening about the rewrite rather than about pasted material.
    static let rewriteWords = ["prompt", "version", "versión", "rewrite", "rewritten", "revised", "improved", "clearer",
                               "mejorad", "reescrit", "revisad", "más clar", "optimi"]
    /// Openings that describe the rewrite itself.
    static let rewriteNarration = ["i've rewritten", "i have rewritten", "i rewrote", "i've improved", "i've revised",
                                   "he reescrito", "he mejorado", "he revisado"]
    /// Closing lines that talk to the person instead of the target.
    static let closingPhrases = ["i hope this helps", "hope this helps", "espero que te sirva", "espero que te ayude",
                                 "espero que esto te", "¿quieres que", "¿te gustaría que", "would you like me to",
                                 "do you want me to", "si quieres, puedo", "if you'd like, i can", "if you want, i can",
                                 "feel free to ask", "let me know if you'd like", "let me know if you want"]
    /// "Let me know …" counts as commentary only when it offers more changes.
    static let letMeKnowWords = ["change", "adjust", "tweak", "modif", "version", "prompt", "further", "anything else", "another"]

    /// Fails when the first line reads as a preface or the last as a remark to the person. A line
    /// that also appears in the draft is never counted.
    static func prefaceOrCommentary(_ output: String, draft: String) -> CheckResult {
        let lines = TextAnalysis.nonBlankLines(output)
        guard let first = lines.first, let last = lines.last else {
            return .pass(Name.noPrefaceOrCommentary)
        }
        let draftLines = Set(TextAnalysis.nonBlankLines(draft).map { normalizedLine($0) })
        var problems: [String] = []
        let firstLine = normalizedLine(first)
        if !draftLines.contains(firstLine), isPreface(firstLine) {
            problems.append("first line reads as a preface: \"\(TextAnalysis.excerpt(first))\"")
        }
        let lastLine = normalizedLine(last)
        if !draftLines.contains(lastLine), isClosingCommentary(lastLine) {
            problems.append("last line reads as commentary: \"\(TextAnalysis.excerpt(last))\"")
        }
        return problems.isEmpty ? .pass(Name.noPrefaceOrCommentary) : .fail(Name.noPrefaceOrCommentary, problems.joined(separator: "; "))
    }

    /// Lowercased, trimmed, without leading Markdown emphasis, heading marks, quote marks or `>`.
    static func normalizedLine(_ line: some StringProtocol) -> String {
        let decoration: Set<Character> = ["#", "*", "_", ">", "\"", "“", "”", "'", "«", " ", "\t", "`"]
        return String(line.drop { decoration.contains($0) }).trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func isPreface(_ line: String) -> Bool {
        for opening in chattyOpenings where line.hasPrefix(opening) {
            let next = line.dropFirst(opening.count).first
            if next == nil || [",", "!", ".", ":", "—", "-"].contains(next!) { return true }
        }
        if presentingOpenings.contains(where: line.hasPrefix), rewriteWords.contains(where: line.contains) {
            return true
        }
        return rewriteNarration.contains(where: line.hasPrefix)
    }

    static func isClosingCommentary(_ line: String) -> Bool {
        if closingPhrases.contains(where: line.contains) { return true }
        if line.hasPrefix("let me know") { return letMeKnowWords.contains(where: line.contains) }
        return false
    }

    // MARK: - Fences

    /// Fails when one code fence wraps the whole output, unless the draft itself was wrapped.
    static func wrappingFence(_ output: String, draft: String) -> CheckResult {
        guard !TextAnalysis.isWhollyFenced(draft) else {
            return .pass(Name.noWrappingFence, "the draft itself is wholly fenced")
        }
        return TextAnalysis.isWhollyFenced(output)
            ? .fail(Name.noWrappingFence, "the whole output is wrapped in a code fence")
            : .pass(Name.noWrappingFence)
    }

    /// Fails on fenced code blocks that are not allowed, or on the wrong number of them.
    static func codeFences(_ output: String, allowed: Bool, exactly expected: Int?) -> CheckResult {
        let blocks = TextAnalysis.codeBlocks(in: output)
        if let expected, blocks.count != expected {
            return .fail(Name.codeFences, "expected exactly \(expected) fenced code block(s), found \(blocks.count)")
        }
        if !allowed, !blocks.isEmpty {
            return .fail(Name.codeFences, "found \(blocks.count) fenced code block(s); the draft had none")
        }
        return .pass(Name.codeFences, "\(blocks.count) fenced code block(s)")
    }

    // MARK: - Fidelity

    static func preservedVerbatim(_ output: String, required: [String]) -> CheckResult {
        let missing = required.filter { !output.contains($0) }
        guard missing.isEmpty else {
            return .fail(Name.preservedVerbatim, "missing or altered: " + missing.map { "\"\(TextAnalysis.excerpt($0, limit: 60))\"" }.joined(separator: ", "))
        }
        return .pass(Name.preservedVerbatim, "\(required.count) kept exactly")
    }

    /// Fails when the output has a `{{…}}` variable the draft did not.
    static func inventedVariables(_ output: String, draft: String) -> CheckResult {
        let invented = TextAnalysis.mustacheVariables(output).subtracting(TextAnalysis.mustacheVariables(draft))
        guard invented.isEmpty else {
            return .fail(Name.noInventedVariables, "new {{…}} variables: " + invented.sorted().joined(separator: ", "))
        }
        return .pass(Name.noInventedVariables)
    }

    static func mustContain(_ output: String, _ required: [String]) -> CheckResult {
        let missing = required.filter { output.range(of: $0, options: .caseInsensitive) == nil }
        guard missing.isEmpty else {
            return .fail(Name.mustContain, "missing: " + missing.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return .pass(Name.mustContain)
    }

    static func mustNotContain(_ output: String, _ forbidden: [String]) -> CheckResult {
        let found = forbidden.filter { output.range(of: $0, options: .caseInsensitive) != nil }
        guard found.isEmpty else {
            return .fail(Name.mustNotContain, "contains: " + found.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return .pass(Name.mustNotContain)
    }

    static func mustMatch(_ output: String, _ patterns: [String]) -> CheckResult {
        var problems: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                problems.append("invalid pattern \(pattern)")
                continue
            }
            if TextAnalysis.firstMatch(of: regex, in: output) == nil {
                problems.append("no match for \(pattern)")
            }
        }
        return problems.isEmpty ? .pass(Name.mustMatch) : .fail(Name.mustMatch, problems.joined(separator: "; "))
    }

    static func mustNotMatch(_ output: String, _ patterns: [String]) -> CheckResult {
        var problems: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                problems.append("invalid pattern \(pattern)")
                continue
            }
            if let match = TextAnalysis.firstMatch(of: regex, in: output) {
                problems.append("\"\(TextAnalysis.excerpt(match, limit: 60))\" matches \(pattern)")
            }
        }
        return problems.isEmpty ? .pass(Name.mustNotMatch) : .fail(Name.mustNotMatch, problems.joined(separator: "; "))
    }

    // MARK: - Language

    /// Fewer letters than this and the recognizer is guessing.
    static let minimumLettersForLanguage = 15

    /// Nil when the fixture does not check the language (`und`).
    static func language(_ output: String, expected: String) -> CheckResult? {
        let expected = TextAnalysis.primaryLanguage(expected)
        guard expected != "und" else { return nil }
        let letters = TextAnalysis.letterCount(output)
        guard letters >= minimumLettersForLanguage else {
            return .pass(Name.language, "too little prose to tell (\(letters) letters)")
        }
        let guess = TextAnalysis.language(of: output)
        let detected = guess.dominant.map(TextAnalysis.primaryLanguage)
        guard detected == expected else {
            return .fail(Name.language, "expected \(expected), detected \(detected ?? "nothing") (\(guess.summary))")
        }
        return .pass(Name.language, guess.summary)
    }

    // MARK: - Length

    /// Checks every bound the rule sets: word counts, the ratio to the draft and, for a
    /// refinement, the ratio to the first output.
    static func length(_ output: String, rule: LengthRule, draft: String, previous: String?) -> CheckResult {
        let words = TextAnalysis.wordCount(output)
        let draftWords = max(1, TextAnalysis.wordCount(draft))
        var problems: [String] = []
        var facts = ["\(words) words"]
        if let maximum = rule.maxWords, words > maximum {
            problems.append("\(words) words > \(maximum)")
        }
        if let minimum = rule.minWords, words < minimum {
            problems.append("\(words) words < \(minimum)")
        }
        if let ratio = rule.ratio {
            let value = Double(words) / Double(draftWords)
            facts.append(String(format: "%.2f× the draft's %d", value, draftWords))
            if let minimum = ratio.min, value < minimum {
                problems.append(String(format: "%.2f× the draft's %d words < %.2f×", value, draftWords, minimum))
            }
            if let maximum = ratio.max, value > maximum {
                problems.append(String(format: "%.2f× the draft's %d words > %.2f×", value, draftWords, maximum))
            }
        }
        if rule.isRelativeToPrevious {
            if let previous {
                let previousWords = max(1, TextAnalysis.wordCount(previous))
                let value = Double(words) / Double(previousWords)
                facts.append(String(format: "%.2f× the first output's %d", value, previousWords))
                if let by = rule.shorterThanPreviousBy, value > 1 - by {
                    problems.append(String(format: "revision is %.2f× the first output's %d words; needs ≤ %.2f×", value, previousWords, 1 - by))
                }
                if let by = rule.longerThanPreviousBy, value < 1 + by {
                    problems.append(String(format: "revision is %.2f× the first output's %d words; needs ≥ %.2f×", value, previousWords, 1 + by))
                }
            } else {
                problems.append("no first output to compare the revision with")
            }
        }
        return problems.isEmpty ? .pass(Name.length, facts.joined(separator: ", ")) : .fail(Name.length, problems.joined(separator: "; "))
    }

    // MARK: - Leakage

    /// Fails when the output carries the engine's markup, a canary from `core.txt` or the run's
    /// draft id, unless the draft itself contained it.
    static func leakage(_ output: String, draft: String, draftID: String) -> CheckResult {
        let lowerOutput = output.lowercased()
        let lowerDraft = draft.lowercased()
        var leaked: [String] = []
        for marker in LeakMarkers.markup + LeakMarkers.canaries {
            let lower = marker.lowercased()
            if lowerOutput.contains(lower), !lowerDraft.contains(lower) {
                leaked.append("\"\(marker)\"")
            }
        }
        if !draftID.isEmpty, !lowerDraft.contains(draftID.lowercased()) {
            // A letters-only id can be an ordinary word, so the bare id only counts when it has a
            // digit; the attribute form always counts.
            if output.contains("id=\"\(draftID)\"") {
                leaked.append("the draft id attribute")
            } else if draftID.contains(where: \.isNumber), TextAnalysis.containsToken(draftID, in: output) {
                leaked.append("the draft id \(draftID)")
            }
        }
        return leaked.isEmpty ? .pass(Name.noLeakage) : .fail(Name.noLeakage, "leaked " + leaked.joined(separator: ", "))
    }

    // MARK: - Shape

    static func fillIn(_ output: String) -> CheckResult {
        let fillIns = TextAnalysis.fillIns(output)
        guard !fillIns.isEmpty else {
            return .fail(Name.fillIn, "no [fill-in] found")
        }
        return .pass(Name.fillIn, fillIns.sorted().prefix(3).joined(separator: ", "))
    }

    static func listItems(_ output: String, maximum: Int) -> CheckResult {
        let count = TextAnalysis.listItemCount(output)
        guard count <= maximum else {
            return .fail(Name.listItems, "\(count) list items > \(maximum): reads as an answer, not a prompt")
        }
        return .pass(Name.listItems, "\(count) list items")
    }

    static func similarity(_ output: String, draft: String, minimum: Double) -> CheckResult {
        let value = TextAnalysis.similarity(output, draft)
        let detail = String(format: "similarity %.2f (needs ≥ %.2f)", value, minimum)
        return value >= minimum ? .pass(Name.similarity, detail) : .fail(Name.similarity, detail)
    }
}
