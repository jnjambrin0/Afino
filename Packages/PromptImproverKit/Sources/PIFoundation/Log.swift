import os

/// Unified logging for Afino. One `Logger` per area, so `log stream` can be filtered with
/// `--predicate 'subsystem == "com.jnjambrin0.PromptImprover" && category == "engine"'`.
///
/// Never log a draft, a result, a request body or an API key: log sizes, counts, status codes and
/// request identifiers only.
public enum Log {
    /// The running app's bundle identifier (`AppIdentity`).
    public static let subsystem = AppIdentity.bundleIdentifier

    /// The area a message comes from, used as the logger's category.
    public enum Category: String, CaseIterable, Sendable {
        case app
        case panel
        case shortcut
        case engine
        case network
        case secrets
        case store
        case updates
    }

    /// A logger for `category` in Afino's subsystem.
    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
