import Foundation

/// The random id carried by `<draft id="…">` and `</draft id="…">`.
///
/// Because the id never occurs in the draft, a literal `</draft>` (or a forged closing tag) inside
/// the draft cannot end it early.
enum DraftID {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789".utf8)
    static let lengths = 4...6
    /// Random tries before the deterministic fallback. With a working generator a 30,000-character
    /// draft makes a single collision unlikely (under 2 %), so the fallback exists only to guarantee
    /// termination with a degenerate generator.
    static let maxRandomAttempts = 64

    /// One random candidate: 4–6 lowercase letters and digits.
    static func candidate(using generator: inout some RandomNumberGenerator) -> String {
        let length = Int.random(in: lengths, using: &generator)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(length)
        for _ in 0..<length {
            bytes.append(alphabet[Int.random(in: 0..<alphabet.count, using: &generator)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A fresh id that does not occur anywhere in `draft`, compared case-insensitively.
    static func make(avoiding draft: String, using generator: inout some RandomNumberGenerator) -> String {
        let haystack = Array(draft.lowercased().utf8)
        for _ in 0..<maxRandomAttempts {
            let id = candidate(using: &generator)
            if haystack.firstRange(of: id.utf8) == nil {
                return id
            }
        }
        return fallback(avoiding: haystack)
    }

    /// The smallest base-36 number whose 6-character spelling is not among the draft's 6-byte
    /// windows. A draft would need billions of bytes to contain them all.
    private static func fallback(avoiding haystack: [UInt8]) -> String {
        let length = lengths.upperBound
        var present = Set<Int>()
        if haystack.count >= length {
            for start in 0...(haystack.count - length) {
                if let value = value(of: haystack[start..<(start + length)]) {
                    present.insert(value)
                }
            }
        }
        var value = 0
        while present.contains(value) {
            value += 1
        }
        var bytes = [UInt8](repeating: alphabet[0], count: length)
        for position in stride(from: length - 1, through: 0, by: -1) {
            bytes[position] = alphabet[value % alphabet.count]
            value /= alphabet.count
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func value(of window: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in window {
            guard let digit = alphabet.firstIndex(of: byte) else { return nil }
            value = value * alphabet.count + digit
        }
        return value
    }
}
