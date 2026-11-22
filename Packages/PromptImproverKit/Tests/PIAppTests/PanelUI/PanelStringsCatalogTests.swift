import Foundation
@testable import PIApp
import PIProviders
import Testing

/// Every panel string is in `Panel.xcstrings` in English and Spanish, and nothing in the catalog
/// is left unused.
struct PanelStringsCatalogTests {
    private static var packageRoot: URL {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) { return directory }
            directory = directory.deletingLastPathComponent()
        }
        return directory
    }

    private static var catalogURL: URL {
        packageRoot.appending(path: "Sources/PIApp/Resources/Panel.xcstrings")
    }

    private static var stringsSourceURL: URL {
        packageRoot.appending(path: "Sources/PIApp/PanelUI/PanelStrings.swift")
    }

    /// The keys `PanelStrings` looks up: `t("…")`, `f("…", …)` and the plural count.
    private static func keysUsedInCode() throws -> Set<String> {
        let source = try String(contentsOf: stringsSourceURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\b[tf]\("([^"]+)""#)
        var keys = Set(regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
        if source.contains(#"String(localized: "history.count \(count)""#) {
            keys.insert("history.count %lld")
        }
        return keys
    }

    private static func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(json?["strings"] as? [String: Any])
    }

    /// The values of one language: the string, or every plural form.
    private static func values(of entry: Any?, language: String) -> [String] {
        guard let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any],
              let localization = localizations[language] as? [String: Any] else { return [] }
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    private static func specifiers(in value: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"%(\d\$)?(@|d|lld)"#)
        return (regex?.matches(in: value, range: NSRange(value.startIndex..., in: value)) ?? []).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }.sorted()
    }

    @Test func everyKeyTheCodeUsesHasEnglishAndSpanish() throws {
        let keys = try Self.keysUsedInCode()
        let catalog = try Self.catalog()
        #expect(keys.count > 100)
        for key in keys.sorted() {
            let english = Self.values(of: catalog[key], language: "en")
            let spanish = Self.values(of: catalog[key], language: "es")
            #expect(!english.isEmpty && english.allSatisfy { !$0.isEmpty }, "\(key) has no English")
            #expect(!spanish.isEmpty && spanish.allSatisfy { !$0.isEmpty }, "\(key) has no Spanish")
        }
    }

    @Test func theCatalogHasNoUnusedKeys() throws {
        let unused = Set(try Self.catalog().keys).subtracting(try Self.keysUsedInCode())
        #expect(unused.isEmpty, "\(unused.sorted())")
    }

    @Test func translationsKeepTheirPlaceholders() throws {
        let catalog = try Self.catalog()
        for (key, entry) in catalog {
            let english = Self.values(of: entry, language: "en").map(Self.specifiers(in:))
            let spanish = Self.values(of: entry, language: "es").map(Self.specifiers(in:))
            #expect(Set(english) == Set(spanish), "\(key)")
        }
    }

    @Test func everyProblemLineHasItsString() throws {
        let catalog = try Self.catalog()
        let lines: [PanelProblemLine] = [
            .invalidKey(nil), .noKey(.anthropic), .noCredit(nil), .modelUnavailable(""), .rateLimited(seconds: 1),
            .rateLimited(seconds: nil), .overloaded(nil), .serverError(nil), .offline, .timeout(seconds: 1), .dropped,
            .droppedEarly, .secureConnection, .refusal, .truncated, .truncatedEmpty, .emptyOutput, .malformed(nil),
            .invalidRequest(nil), .permissionDenied(nil), .contextTooLong, .stopped, .generic,
        ]
        for line in lines {
            #expect(catalog[line.key] != nil, "\(line.key)")
        }
    }

    @Test func theCompiledBundleHasBothLanguages() throws {
        for (language, improve) in [("en", "Improve"), ("es", "Mejorar")] {
            let path = try #require(PanelStrings.bundle.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "action.improve", value: "missing", table: PanelStrings.table) == improve)
        }
        #expect(PanelStrings.improve == "Improve" || PanelStrings.improve == "Mejorar")
    }

    @Test func formattedStringsFillTheirPlaceholders() {
        #expect(!PanelStrings.rewriteFor("Gemini").contains("%@"))
        #expect(PanelStrings.rewriteFor("Gemini").contains("Gemini"))
        #expect(PanelStrings.versionStepper(2, of: 3).contains("2"))
        #expect(PanelStrings.versionStepper(2, of: 3).contains("3"))
        #expect(PanelStrings.historyCount(1) != PanelStrings.historyCount(2).replacingOccurrences(of: "2", with: "1"))
        #expect(PanelStrings.historyCount(7).contains("7"))
        #expect(!PanelStrings.done(words: 214).contains("%d"))
    }
}
