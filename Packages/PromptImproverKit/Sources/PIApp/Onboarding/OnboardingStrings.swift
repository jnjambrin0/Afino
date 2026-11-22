import Foundation

/// The text of the welcome window, in English and Spanish (`Resources/Onboarding.xcstrings`).
/// Keys are written as literals starting with `welcome.` anywhere in `Onboarding/`, so
/// `OnboardingStringsTests` can check that every key used exists in both languages and that the
/// catalog holds nothing unused.
nonisolated enum OnboardingStrings {
    static let table = "Onboarding"

    /// The bundle that holds the catalog.
    static var bundle: Bundle { .module }

    #if DEBUG
    /// `--welcome-language es`: the welcome (and the Settings controls it reuses) in this
    /// language instead of the process's. Set on the main thread before the window is made.
    nonisolated(unsafe) static var previewLanguage: String?
    #endif

    static func text(_ key: String) -> String {
        #if DEBUG
        if let previewLanguage,
           let path = bundle.path(forResource: previewLanguage, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized.localizedString(forKey: key, value: nil, table: table)
        }
        #endif
        return String(localized: String.LocalizationValue(key), table: table, bundle: bundle)
    }

    /// A catalog entry with its format specifiers filled in, in the user's locale.
    static func text(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}
