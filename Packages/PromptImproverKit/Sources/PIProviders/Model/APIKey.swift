import Foundation

/// An API key the person pasted in for a provider.
///
/// Its value never shows up in string interpolation, `print`, `dump`, `String(reflecting:)` or
/// the debugger's summary: all of them read `sk-…last4`. `rawValue` is the only way to the
/// secret, and each provider reads it in one place, the auth header. Deliberately not `Codable`:
/// keys live in the Keychain, never in a settings or history file.
public struct APIKey: Sendable, Hashable {
    /// The secret itself. Read it only to build an auth header.
    public let rawValue: String

    /// - Parameter rawValue: The key as pasted; surrounding whitespace and newlines are dropped.
    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when there is no key at all (the provider then fails with `.missingKey`).
    public var isEmpty: Bool { rawValue.isEmpty }

    /// `sk-…` and the last four characters, or a bare `…` for a key too short to show any of.
    public var masked: String {
        guard rawValue.count >= 12 else { return "…" }
        let prefix = rawValue.hasPrefix("sk-") ? "sk-" : ""
        return prefix + "…" + rawValue.suffix(4)
    }
}

/// Every textual and reflected form shows the masked key only.
extension APIKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { masked }
    public var debugDescription: String { "APIKey(\(masked))" }
    public var customMirror: Mirror { Mirror(self, children: ["masked": masked], displayStyle: .struct) }
}
