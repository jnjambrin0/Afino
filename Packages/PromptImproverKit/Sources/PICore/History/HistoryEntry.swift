import Foundation

/// One improvement the user ran: what they typed, who it was for and every version the engine
/// wrote (the first result plus each refinement or regeneration).
public nonisolated struct HistoryEntry: Codable, Sendable, Identifiable, Equatable {
    /// Stays the same while the session refines the run, so each refinement updates this entry.
    public var id: UUID
    /// When the latest version was recorded.
    public var date: Date
    /// The draft exactly as the user submitted it.
    public var draft: String
    /// The target pack's stable id (`"claude"`, `"gpt"`…).
    public var targetID: String
    /// Every complete version, oldest first. Never empty.
    public var versions: [Version]
    /// The provider (`ProviderID` raw value) that produced the latest version.
    public var provider: String
    /// The model that produced the latest version, shown in the result's "written by" tooltip
    /// when the entry is opened again.
    public var model: String

    /// One complete prompt the engine wrote.
    public nonisolated struct Version: Codable, Sendable, Equatable {
        /// The finished text, as it was shown and copied.
        public var text: String
        /// The refine instruction that led to this version; `nil` for the first one and for
        /// plain regenerations.
        public var instruction: String?
        /// The target this version was written for, when it differs from the entry's (a result
        /// rewritten for another model). `nil` means the entry's `targetID`.
        public var targetID: String?

        public init(text: String, instruction: String? = nil, targetID: String? = nil) {
            self.text = text
            self.instruction = instruction
            self.targetID = targetID
        }
    }

    public init(
        id: UUID = UUID(), date: Date = Date(), draft: String, targetID: String,
        versions: [Version], provider: String, model: String
    ) {
        self.id = id
        self.date = date
        self.draft = draft
        self.targetID = targetID
        self.versions = versions
        self.provider = provider
        self.model = model
    }

    /// The version the user last saw.
    public var latestText: String { versions.last?.text ?? "" }
}
