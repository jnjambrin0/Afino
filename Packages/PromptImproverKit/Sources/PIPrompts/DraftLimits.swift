import Foundation

/// The outcome of checking a draft against `DraftLimits`, for the panel to show.
public struct DraftValidation: Sendable, Hashable {
    /// Where the draft stands against the limits.
    public enum Status: Sendable, Hashable {
        /// Empty or only whitespace: Improve is disabled.
        case empty
        /// Within the soft limit.
        case acceptable
        /// Over the soft limit: submittable, with a gentle warning.
        case long
        /// Over the hard limit: not submittable. The draft is never truncated.
        case tooLong
    }

    /// Where the draft stands against the limits.
    public let status: Status
    /// Characters (grapheme clusters), as a person counts them.
    public let characterCount: Int

    public init(status: Status, characterCount: Int) {
        self.status = status
        self.characterCount = characterCount
    }

    /// Whether Improve may send the draft.
    public var isSubmittable: Bool {
        status == .acceptable || status == .long
    }

    /// Whether to show the soft "long draft" warning.
    public var showsLengthWarning: Bool {
        status == .long
    }
}

/// Size limits for a draft.
public enum DraftLimits {
    /// Above this many characters a soft warning is shown.
    public static let softLimit = 8_000
    /// Above this many characters the draft cannot be submitted.
    public static let hardLimit = 30_000

    /// Where `draft` stands against the limits.
    public static func validate(_ draft: String) -> DraftValidation {
        let count = draft.count
        let status: DraftValidation.Status =
            if TextNormalization.isBlank(draft) {
                .empty
            } else if count > hardLimit {
                .tooLong
            } else if count > softLimit {
                .long
            } else {
                .acceptable
            }
        return DraftValidation(status: status, characterCount: count)
    }
}
