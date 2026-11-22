import Foundation

/// A target the prompt is written for: a model family such as Claude or GPT, never a specific
/// model version.
///
/// Each pack ships as `Resources/Packs/<id>/pack.json` (the metadata below, without `guidance`) plus
/// `Resources/Packs/<id>/guidance.md` (the distilled prompting advice placed in the system prompt).
/// Packs change only with an app release.
public struct TargetPack: Codable, Sendable, Identifiable, Hashable {
    /// Where a piece of the guidance comes from.
    public struct Source: Codable, Sendable, Hashable {
        /// The document's title.
        public let title: String
        /// Where it is published; the loader accepts only `https`.
        public let url: URL
        /// The day it was read, `yyyy-MM-dd`.
        public let retrievedOn: String

        public init(title: String, url: URL, retrievedOn: String) {
            self.title = title
            self.url = url
            self.retrievedOn = retrievedOn
        }
    }

    /// How the target is drawn in the picker: a two-letter monogram or an SF Symbol name.
    public enum Badge: Sendable, Hashable {
        case monogram(String)
        case symbol(String)
    }

    /// The `schemaVersion` of `pack.json` this build understands.
    public static let supportedSchemaVersion = 1

    /// The `pack.json` schema the pack was written for.
    public let schemaVersion: Int
    /// Stable identifier, also the pack's folder name (`claude`, `gpt`, `gemini`, `generic`).
    public let id: String
    /// Short name for the picker ("Claude", "Any model").
    public let displayName: String
    /// `anthropic`, `openai`, `google` or `generic`. Informational only.
    public let vendorFamily: String
    /// How the target is named to the engine ("Claude (Anthropic)", "an AI model").
    public let promptLabel: String
    /// Which models the guidance covers, in one line.
    public let coversModels: String
    /// A two-letter monogram for the picker. Exactly one of `monogram` and `symbol` is set in a
    /// valid pack; see `badge`.
    public let monogram: String?
    /// An SF Symbol name for the picker, for a target without a vendor to abbreviate.
    public let symbol: String?
    /// Position in the picker, ascending.
    public let sortOrder: Int
    /// The documents the guidance was distilled from.
    public let sources: [Source]
    /// The guidance's own version, such as `2026.11.1`.
    public let packVersion: String
    /// Day the guidance was last checked against its sources, `yyyy-MM-dd`.
    public let reviewedOn: String
    /// Content of `guidance.md`: line endings normalised to LF, outer whitespace trimmed.
    public let guidance: String

    public init(
        schemaVersion: Int = TargetPack.supportedSchemaVersion,
        id: String,
        displayName: String,
        vendorFamily: String,
        promptLabel: String,
        coversModels: String,
        monogram: String? = nil,
        symbol: String? = nil,
        sortOrder: Int,
        sources: [Source] = [],
        packVersion: String,
        reviewedOn: String,
        guidance: String
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.vendorFamily = vendorFamily
        self.promptLabel = promptLabel
        self.coversModels = coversModels
        self.monogram = monogram
        self.symbol = symbol
        self.sortOrder = sortOrder
        self.sources = sources
        self.packVersion = packVersion
        self.reviewedOn = reviewedOn
        self.guidance = TextNormalization.trimmed(TextNormalization.normalizingLineEndings(guidance))
    }

    /// The monogram when there is one, else the symbol. A hand-built pack with neither falls back to
    /// the first two letters of its display name.
    public var badge: Badge {
        if let monogram, !TextNormalization.isBlank(monogram) { return .monogram(monogram) }
        if let symbol, !TextNormalization.isBlank(symbol) { return .symbol(symbol) }
        return .monogram(String(displayName.prefix(2)))
    }

    /// `reviewedOn` as midnight UTC, or nil when it is not a valid `yyyy-MM-dd` day.
    public var reviewDate: Date? {
        Self.parseDay(reviewedOn)
    }

    /// Strict `yyyy-MM-dd` (UTC) parsing: impossible days such as `2026-02-30` are rejected
    /// instead of rolling over.
    static func parseDay(_ string: String) -> Date? {
        let style = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        guard let date = try? style.parse(string), style.format(date) == string else { return nil }
        return date
    }
}
