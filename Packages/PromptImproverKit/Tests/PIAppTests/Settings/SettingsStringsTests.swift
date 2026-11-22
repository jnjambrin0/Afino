import Foundation
@testable import PIApp
import Testing

/// Every `settings.*` and `status.*` key written in the Settings and menu bar sources exists in
/// `Settings.xcstrings` in English and Spanish, and the catalog holds no key the code doesn't use.
struct SettingsStringsTests {
    private static let keyPattern = try! NSRegularExpression(pattern: #""((?:settings|status)\.[A-Za-z0-9_.]+)""#)

    private static var packageRoot: URL {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return directory
    }

    private static func keysUsedInCode() throws -> Set<String> {
        let app = packageRoot.appending(path: "Sources/PIApp")
        let folders = [app.appending(path: "Settings"), app.appending(path: "Shell")]
        var keys = Set<String>()
        for folder in folders {
            let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                let range = NSRange(source.startIndex..., in: source)
                for match in keyPattern.matches(in: source, range: range) {
                    if let key = Range(match.range(at: 1), in: source) {
                        keys.insert(String(source[key]))
                    }
                }
            }
        }
        return keys
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    let state: String
                    let value: String
                }

                let stringUnit: Unit
            }

            let localizations: [String: Localization]
        }

        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private static func catalog() throws -> Catalog {
        let url = packageRoot.appending(path: "Sources/PIApp/Resources/Settings.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test func everyKeyInCodeIsTranslated() throws {
        let used = try Self.keysUsedInCode()
        #expect(used.count > 100)
        let catalog = try Self.catalog()
        #expect(catalog.sourceLanguage == "en")
        for key in used.sorted() {
            let entry = try #require(catalog.strings[key], "\(key) is not in Settings.xcstrings")
            for language in ["en", "es"] {
                let unit = entry.localizations[language]?.stringUnit
                #expect(unit?.state == "translated", "\(key) has no \(language) translation")
                #expect(unit?.value.isEmpty == false, "\(key) is empty in \(language)")
            }
        }
    }

    @Test func theCatalogHoldsNothingUnused() throws {
        let used = try Self.keysUsedInCode()
        let unused = Set(try Self.catalog().strings.keys).subtracting(used)
        #expect(unused.isEmpty, "Unused keys: \(unused.sorted())")
    }

    @Test func formatSpecifiersMatchAcrossLanguages() throws {
        let specifier = try NSRegularExpression(pattern: #"%(\d\$)?@"#)
        for (key, entry) in try Self.catalog().strings {
            let counts = ["en", "es"].map { language -> Int in
                let value = entry.localizations[language]?.stringUnit.value ?? ""
                return specifier.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
            }
            #expect(counts[0] == counts[1], "\(key) has different format specifiers in en and es")
        }
    }

    @Test func theBuiltBundleHasBothLanguages() throws {
        for language in ["en", "es"] {
            let path = try #require(SettingsStrings.bundle.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
            let bundle = try #require(Bundle(path: path))
            let value = bundle.localizedString(forKey: "settings.pane.engine", value: nil, table: SettingsStrings.table)
            #expect(value == (language == "en" ? "Engine" : "Motor"))
        }
    }
}
