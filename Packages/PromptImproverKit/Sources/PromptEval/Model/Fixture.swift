import Foundation
import PIPrompts

/// A length requirement on an output. Every field that is set is checked.
struct LengthRule: Codable, Sendable, Hashable {
    /// Bounds on the output's word count divided by the draft's.
    struct Ratio: Codable, Sendable, Hashable {
        var min: Double?
        var max: Double?
    }

    var maxWords: Int?
    var minWords: Int?
    var ratio: Ratio?
    /// Refinements only: the revised output has at most `(1 − value) ×` the first output's words.
    var shorterThanPreviousBy: Double?
    /// Refinements only: the revised output has at least `(1 + value) ×` the first output's words.
    var longerThanPreviousBy: Double?

    init(
        maxWords: Int? = nil,
        minWords: Int? = nil,
        ratio: Ratio? = nil,
        shorterThanPreviousBy: Double? = nil,
        longerThanPreviousBy: Double? = nil
    ) {
        self.maxWords = maxWords
        self.minWords = minWords
        self.ratio = ratio
        self.shorterThanPreviousBy = shorterThanPreviousBy
        self.longerThanPreviousBy = longerThanPreviousBy
    }

    var isEmpty: Bool { self == LengthRule() }

    /// Whether the rule compares against the first output of a refinement.
    var isRelativeToPrevious: Bool { shorterThanPreviousBy != nil || longerThanPreviousBy != nil }
}

/// The standing preferences a fixture runs with, as `PromptPreferences` takes them.
struct FixturePreferences: Codable, Sendable, Hashable {
    var customInstructions: String?
    var language: OutputLanguage?

    var promptPreferences: PromptPreferences {
        PromptPreferences(
            customInstructions: customInstructions ?? "",
            customInstructionsEnabled: true,
            language: language ?? .matchDraft
        )
    }
}

/// One evaluation case: a draft, the target it is rewritten for, and what a good output satisfies.
///
/// Stored as one JSON file per fixture in `Sources/PromptEval/Fixtures/`. A variant
/// (`variantOf`) inherits the draft and target of its base fixture; everything else is its own.
/// Text comparisons in `mustContain` and `mustNotContain` ignore case; `preserveVerbatim` is exact.
struct Fixture: Sendable, Hashable, Identifiable {
    var id: String
    /// One line, shown by `prompt-eval list`.
    var title: String
    /// The fixture whose draft and target this one reuses.
    var variantOf: String?
    /// What the person typed, exactly.
    var draft: String
    /// A target pack id: `claude`, `gpt`, `gemini` or `generic`.
    var target: String
    /// BCP-47 language of a good output (`en`, `es`), or `und` to skip the language check.
    var expectedLanguage: String
    var preferences: FixturePreferences?
    /// A revision request sent as a second turn after the first output.
    var refine: String?
    /// Strings the output must contain, ignoring case.
    var mustContain: [String]
    /// Strings the output must not contain, ignoring case.
    var mustNotContain: [String]
    /// Regular expressions (ICU syntax) the output must match.
    var mustMatch: [String]
    /// Regular expressions (ICU syntax) the output must not match.
    var mustNotMatch: [String]
    /// Strings that must appear in the output character for character.
    var preserveVerbatim: [String]
    var length: LengthRule?
    /// Whether a `[…]` fill-in must appear.
    var expectFillIn: Bool
    /// Whether fenced code blocks are allowed; nil means "only when the draft has one".
    var allowCodeFence: Bool?
    /// The exact number of fenced code blocks, when it matters.
    var codeBlocks: Int?
    /// The most list-item lines the output may have.
    var maxListItems: Int?
    /// The least word-overlap similarity (0–1) between output and draft.
    var minSimilarityToDraft: Double?
    /// Whether `prompt-eval smoke` runs this fixture.
    var inSmoke: Bool
    /// Why the fixture exists and what a good output does. For people reading the fixture; no
    /// check uses it.
    var notes: String?

    init(
        id: String,
        title: String = "",
        variantOf: String? = nil,
        draft: String,
        target: String,
        expectedLanguage: String,
        preferences: FixturePreferences? = nil,
        refine: String? = nil,
        mustContain: [String] = [],
        mustNotContain: [String] = [],
        mustMatch: [String] = [],
        mustNotMatch: [String] = [],
        preserveVerbatim: [String] = [],
        length: LengthRule? = nil,
        expectFillIn: Bool = false,
        allowCodeFence: Bool? = nil,
        codeBlocks: Int? = nil,
        maxListItems: Int? = nil,
        minSimilarityToDraft: Double? = nil,
        inSmoke: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.variantOf = variantOf
        self.draft = draft
        self.target = target
        self.expectedLanguage = expectedLanguage
        self.preferences = preferences
        self.refine = refine
        self.mustContain = mustContain
        self.mustNotContain = mustNotContain
        self.mustMatch = mustMatch
        self.mustNotMatch = mustNotMatch
        self.preserveVerbatim = preserveVerbatim
        self.length = length
        self.expectFillIn = expectFillIn
        self.allowCodeFence = allowCodeFence
        self.codeBlocks = codeBlocks
        self.maxListItems = maxListItems
        self.minSimilarityToDraft = minSimilarityToDraft
        self.inSmoke = inSmoke
        self.notes = notes
    }

    /// The preferences the run sends (defaults when the fixture has none).
    var promptPreferences: PromptPreferences {
        (preferences ?? FixturePreferences()).promptPreferences
    }

    /// Whether code fences are allowed in the output.
    var codeFencesAllowed: Bool {
        allowCodeFence ?? !TextAnalysis.codeBlocks(in: draft).isEmpty
    }

    /// Short drafts are the ones the latency targets are measured on.
    var isShort: Bool { draft.count <= Self.shortDraftCharacters }

    /// The longest draft, in characters, that counts as short.
    static let shortDraftCharacters = 280

    /// Number of requests one run of this fixture sends.
    var requestCount: Int { refine == nil ? 1 : 2 }
}

extension Fixture: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, variantOf, draft, target, expectedLanguage, preferences, refine
        case mustContain, mustNotContain, mustMatch, mustNotMatch, preserveVerbatim, length
        case expectFillIn, allowCodeFence, codeBlocks, maxListItems, minSimilarityToDraft, inSmoke, notes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        variantOf = try container.decodeIfPresent(String.self, forKey: .variantOf)
        // A variant may leave these out; FixtureLibrary fills them in from its base.
        draft = try container.decodeIfPresent(String.self, forKey: .draft) ?? ""
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        expectedLanguage = try container.decode(String.self, forKey: .expectedLanguage)
        preferences = try container.decodeIfPresent(FixturePreferences.self, forKey: .preferences)
        refine = try container.decodeIfPresent(String.self, forKey: .refine)
        mustContain = try container.decodeIfPresent([String].self, forKey: .mustContain) ?? []
        mustNotContain = try container.decodeIfPresent([String].self, forKey: .mustNotContain) ?? []
        mustMatch = try container.decodeIfPresent([String].self, forKey: .mustMatch) ?? []
        mustNotMatch = try container.decodeIfPresent([String].self, forKey: .mustNotMatch) ?? []
        preserveVerbatim = try container.decodeIfPresent([String].self, forKey: .preserveVerbatim) ?? []
        length = try container.decodeIfPresent(LengthRule.self, forKey: .length)
        expectFillIn = try container.decodeIfPresent(Bool.self, forKey: .expectFillIn) ?? false
        allowCodeFence = try container.decodeIfPresent(Bool.self, forKey: .allowCodeFence)
        codeBlocks = try container.decodeIfPresent(Int.self, forKey: .codeBlocks)
        maxListItems = try container.decodeIfPresent(Int.self, forKey: .maxListItems)
        minSimilarityToDraft = try container.decodeIfPresent(Double.self, forKey: .minSimilarityToDraft)
        inSmoke = try container.decodeIfPresent(Bool.self, forKey: .inSmoke) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}
