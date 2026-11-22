import Foundation
@testable import PIApp
import Testing

/// Every `welcome.*` key written in the welcome's sources exists in `Onboarding.xcstrings` in
/// English and Spanish, with the same format specifiers, and the catalog holds nothing unused.
struct OnboardingStringsTests {
    private static let keyPattern = try! NSRegularExpression(pattern: #""(welcome\.[A-Za-z0-9_.]+)""#)

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
        let folder = packageRoot.appending(path: "Sources/PIApp/Onboarding")
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var keys = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for match in keyPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let key = Range(match.range(at: 1), in: source) {
                    keys.insert(String(source[key]))
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
        let url = packageRoot.appending(path: "Sources/PIApp/Resources/Onboarding.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test func everyKeyInCodeIsTranslated() throws {
        let used = try Self.keysUsedInCode()
        #expect(used.count > 60)
        let catalog = try Self.catalog()
        #expect(catalog.sourceLanguage == "en")
        for key in used.sorted() {
            let entry = try #require(catalog.strings[key], "\(key) is not in Onboarding.xcstrings")
            for language in ["en", "es"] {
                let unit = entry.localizations[language]?.stringUnit
                #expect(unit?.state == "translated", "\(key) has no \(language) translation")
                #expect(unit?.value.isEmpty == false, "\(key) is empty in \(language)")
            }
        }
    }

    @Test func theCatalogHoldsNothingUnused() throws {
        let unused = Set(try Self.catalog().strings.keys).subtracting(try Self.keysUsedInCode())
        #expect(unused.isEmpty, "Unused keys: \(unused.sorted())")
    }

    @Test func formatSpecifiersMatchAcrossLanguages() throws {
        let specifier = try NSRegularExpression(pattern: #"%(\d\$)?(@|lld|d)"#)
        func specifiers(_ value: String) -> [String] {
            specifier.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
                .sorted()
        }
        for (key, entry) in try Self.catalog().strings {
            let english = specifiers(entry.localizations["en"]?.stringUnit.value ?? "")
            let spanish = specifiers(entry.localizations["es"]?.stringUnit.value ?? "")
            #expect(english == spanish, "\(key) has different format specifiers in en and es")
        }
    }

    @Test func theBuiltBundleHasBothLanguages() throws {
        for (language, title) in [("en", "Add your API key"), ("es", "Añade tu clave de API")] {
            let path = try #require(OnboardingStrings.bundle.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "welcome.key.title", value: "missing", table: OnboardingStrings.table) == title)
        }
    }

    @Test func formattedStringsFillTheirSpecifiers() {
        #expect(WelcomeStep.apiKey.progress.contains("2"))
        #expect(WelcomeStep.apiKey.progress.contains("4"))
        #expect(!WelcomeStep.apiKey.progress.contains("%"))
        #expect(!WelcomeStep.keys.announcement.contains("%"))
        #expect(OnboardingStrings.text("welcome.key.privacy", "Anthropic").contains("Anthropic"))
        #expect(OnboardingStrings.text("welcome.shortcut.try", "⌃⌥P").contains("⌃⌥P"))
    }
}
