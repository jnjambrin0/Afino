import Foundation

/// The text of Settings, of the controls the welcome window borrows from it (the API key field
/// and the shortcut recorder) and of the menu bar item, in English and Spanish
/// (`Resources/Settings.xcstrings`). Keys are written as literals starting with `settings.` or
/// `status.`, so `SettingsStringsTests` can check that every key used in code exists in both
/// languages and that the catalog holds nothing unused.
nonisolated enum SettingsStrings {
    static let table = "Settings"

    /// The bundle that holds the catalog.
    static var bundle: Bundle { .module }

    #if DEBUG
    /// Debug builds only: renders the text in this language (`"es"`) instead of the process's,
    /// for the snapshot tests and the welcome's `--welcome-language` flag. Set it on the main
    /// thread, before drawing.
    nonisolated(unsafe) static var previewLanguage: String?
    #endif

    static func text(_ key: String) -> String {
        #if DEBUG
        if let previewLanguage,
           let path = Bundle.module.path(forResource: previewLanguage, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized.localizedString(forKey: key, value: nil, table: table)
        }
        #endif
        return String(localized: String.LocalizationValue(key), table: table, bundle: .module)
    }

    /// A catalog entry with its `%@` format specifiers filled in, in the user's locale.
    static func text(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}
