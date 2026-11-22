import Foundation

/// A lenient read-only view of decoded JSON. Missing keys, nulls and values of an unexpected
/// type all read as nil, so a provider adding or reshaping a field never fails a stream.
struct JSONValue {
    let raw: Any?

    init(raw: Any?) {
        self.raw = raw
    }

    /// Throws when `data` is not JSON at all.
    init(parsing data: Data) throws {
        raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    init(parsing text: String) throws {
        try self.init(parsing: Data(text.utf8))
    }

    subscript(key: String) -> JSONValue {
        JSONValue(raw: (raw as? [String: Any])?[key])
    }

    var string: String? { raw as? String }

    var int: Int? {
        guard let number = raw as? NSNumber, !isBoolean(number) else { return nil }
        return number.intValue
    }

    var bool: Bool? {
        guard let number = raw as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    var array: [JSONValue] {
        (raw as? [Any])?.map { JSONValue(raw: $0) } ?? []
    }

    var isObject: Bool { raw is [String: Any] }

    /// A string or a number as text (OpenAI's error `code` has been both).
    var text: String? {
        if let string { return string }
        if let int { return String(int) }
        return nil
    }

    private func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
