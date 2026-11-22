import Foundation

/// Removes secrets from text that came from a provider before it can reach an error, a log or
/// the clipboard ("Copy details"). Providers echo keys in some messages (OpenAI's 401 names a
/// masked key), so every provider message goes through `scrub` first.
enum Redactor {
    /// What a removed secret is replaced with.
    static let placeholder = "[redacted]"

    /// `text` without anything that looks like an API key (`sk-ant-…`, `sk-…`, masked forms
    /// included), without bearer tokens, and without any of `knownSecrets` verbatim.
    static func scrub(_ text: String, knownSecrets: [String] = []) -> String {
        var result = text
        // The exact secrets first, so a key in an unusual format is caught too. Very short
        // strings are skipped: replacing them would mangle ordinary words.
        for secret in knownSecrets where secret.count >= 8 {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }
        let bearer = #/(?i)bearer\s+[A-Za-z0-9\-._~+\/]{8,}=*/#.wordBoundaryKind(.simple)
        result = result.replacing(bearer, with: "Bearer \(placeholder)")
        // `sk-` keys of every kind: sk-ant-api03-…, sk-proj-…, sk-svcacct-…, and masked echoes
        // such as sk-proj-****abcd. The word boundary keeps "task-…" and "disk-…" intact.
        let key = #/\bsk-[A-Za-z0-9_\-*]{6,}/#.wordBoundaryKind(.simple)
        result = result.replacing(key, with: placeholder)
        return result
    }

    /// `scrub`, then shortened to `limit` characters: provider messages end up in one-line errors.
    static func scrubbedMessage(_ text: String, knownSecrets: [String], limit: Int = 300) -> String {
        let clean = scrub(text, knownSecrets: knownSecrets).trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit)) + "…"
    }
}
