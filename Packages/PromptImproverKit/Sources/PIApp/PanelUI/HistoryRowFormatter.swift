import Foundation
import PICore
import PIDesign
import PIPrompts

/// One history row as text: the draft's first line, a preview of the latest result, when, and
/// who it was for.
struct HistoryRowContent: Equatable {
    var title: String
    var preview: String
    /// `nil` means "just now" (the caller shows its localized word).
    var time: String?
    var monogram: EMonogram
}

/// Formats history entries for the ⌘Y list, and filters them. Pure: the clock and the locale
/// are parameters.
enum HistoryRowFormatter {
    /// Entries younger than this read as "now".
    static let nowThreshold: TimeInterval = 60
    static let titleLimit = 120
    static let previewLimit = 160

    static func row(for entry: HistoryEntry, library: TargetPackLibrary, now: Date, locale: Locale = .current) -> HistoryRowContent {
        HistoryRowContent(
            title: firstLine(of: entry.draft, limit: titleLimit),
            preview: firstLine(of: entry.latestText, limit: previewLimit),
            time: relativeTime(from: entry.date, now: now, locale: locale),
            monogram: monogram(for: library.pack(for: entry.targetID))
        )
    }

    /// The first line with text in it, whitespace collapsed, cut at `limit` characters with an
    /// ellipsis. Markdown heading marks and list bullets at its start are dropped: a preview of
    /// "# Role" reads better as "Role".
    static func firstLine(of text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var cleaned = Substring(line)
        while let first = cleaned.first, first == "#" || first == ">" {
            cleaned = cleaned.dropFirst()
        }
        if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
            cleaned = cleaned.dropFirst(2)
        }
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "5 min", "2 h", "3 d"… or nil for less than a minute (and for a date in the future).
    static func relativeTime(from date: Date, now: Date, locale: Locale = .current) -> String? {
        guard now.timeIntervalSince(date) >= nowThreshold else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        return formatter.string(from: date, to: now)
    }

    static func monogram(for pack: TargetPack) -> EMonogram {
        switch pack.badge {
        case .monogram(let letters): .letters(letters)
        case .symbol(let name): .symbol(name)
        }
    }

    /// Entries whose draft or latest result contains every word of `query` (case and
    /// diacritics ignored), in their original order.
    static func filter(_ entries: [HistoryEntry], query: String) -> [HistoryEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = entry.draft + "\n" + entry.latestText
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// The next selection for ↑/↓, wrapping round; nil when the list is empty.
    static func step(from index: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return forward ? 0 : count - 1 }
        return (index + (forward ? 1 : count - 1)) % count
    }
}
