import Foundation

/// Which copy of Afino is running. Its bundle identifier names its data folder, its log subsystem
/// and its Keychain service, as it already names its preferences and its login item, so a build
/// with an identifier of its own (a development build as `com.jnjambrin0.PromptImprover.dev`)
/// keeps everything apart from the published app.
public nonisolated enum AppIdentity {
    /// The identifier Afino ships with. Code that does not run inside an app bundle (tests,
    /// command-line tools) goes by it. It keeps the project's name from before 1.0 so that
    /// existing preferences and Keychain items stay with the app.
    public static let defaultBundleIdentifier = "com.jnjambrin0.PromptImprover"

    /// The running app's bundle identifier, or `defaultBundleIdentifier` outside an app bundle.
    public static let bundleIdentifier = bundleIdentifier(
        declared: Bundle.main.bundleIdentifier,
        bundleURL: Bundle.main.bundleURL
    )

    /// Afino's folder in Application Support: the history file and anything kept from 0.x.
    public static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    /// Afino's folder in Caches: the model lists fetched from each provider.
    public static var cachesDirectory: URL {
        URL.cachesDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    /// The identifier to go by: the declared one inside an app bundle, else the default.
    ///
    /// - Parameters:
    ///   - declared: What the main bundle declares, if anything.
    ///   - bundleURL: Where the main bundle is; only an `.app` counts.
    static func bundleIdentifier(declared: String?, bundleURL: URL) -> String {
        guard bundleURL.pathExtension == "app", let declared, !declared.isEmpty else {
            return defaultBundleIdentifier
        }
        return declared
    }
}
