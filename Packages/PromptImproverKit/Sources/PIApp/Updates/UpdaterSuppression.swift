import Foundation

/// Why Afino does not look for updates on this run. Debug builds never do; a build
/// whose Info.plist lacks the feed or the key that verifies updates cannot (Sparkle would only
/// greet the user with an error); and a copy that cannot replace itself — outside Applications,
/// on a read-only volume, translocated — must not try.
nonisolated enum UpdaterSuppression: Equatable, Sendable {
    /// A Debug build: signed for development and replaced by every rebuild.
    case debugBuild
    /// `SUFeedURL` is missing, empty or not an https URL. A Debug build expands the feed setting,
    /// which only Release defines, to an empty string.
    case missingFeedURL
    /// `SUPublicEDKey` is missing or empty: every update would be rejected.
    case missingPublicKey
    /// The app runs from where an update could not replace it (`InstallLocationManager`).
    case notUpdatableLocation

    /// - Returns: `nil` when the updater may start.
    static func reason(
        infoDictionary: [String: Any],
        isDebugBuild: Bool,
        isUpdatableLocation: Bool
    ) -> UpdaterSuppression? {
        if isDebugBuild { return .debugBuild }
        guard let feed = text(infoDictionary["SUFeedURL"]), URL(string: feed)?.scheme == "https" else {
            return .missingFeedURL
        }
        guard text(infoDictionary["SUPublicEDKey"]) != nil else { return .missingPublicKey }
        guard isUpdatableLocation else { return .notUpdatableLocation }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }
}
