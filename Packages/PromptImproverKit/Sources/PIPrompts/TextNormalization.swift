import Foundation

/// Small text helpers shared by the composer and the post-processor.
enum TextNormalization {
    /// Turns every CRLF pair and every lone CR into LF; nothing else changes.
    static func normalizingLineEndings(_ text: String) -> String {
        guard text.utf8.contains(UInt8(ascii: "\r")) else { return text }
        var scalars = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                scalars.append("\n")
                previousWasCarriageReturn = true
            case "\n" where previousWasCarriageReturn:
                previousWasCarriageReturn = false
            default:
                scalars.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        return String(scalars)
    }

    /// Removes leading and trailing whitespace and newlines.
    static func trimmed(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the text is empty or only whitespace and newlines.
    static func isBlank(_ text: some StringProtocol) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }
}
