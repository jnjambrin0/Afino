@testable import PIApp
import Testing

/// When the updater may start.
struct UpdaterSuppressionTests {
    private let release: [String: Any] = [
        "SUFeedURL": "https://jnjambrin0.github.io/Afino/updates/stable/appcast.xml",
        "SUPublicEDKey": "A9j5LwwY+Qw7dRQtPQQ/N/6YCd5/56DT6jazquGKx/s=",
    ]

    @Test func aReleaseBuildWithFeedAndKeyInApplicationsLooksForUpdates() {
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: false, isUpdatableLocation: true) == nil)
    }

    @Test func debugBuildsNeverDo() {
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: true, isUpdatableLocation: true) == .debugBuild)
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: true, isUpdatableLocation: false) == .debugBuild)
    }

    /// A Debug build expands the feed setting, which only Release defines, to an empty string.
    @Test(arguments: [nil, "", "  ", "http://jnjambrin0.github.io/appcast.xml", "$(SPARKLE_FEED_URL)"])
    func aBuildWithoutAnHTTPSFeedCannot(feed: String?) {
        var info = release
        info["SUFeedURL"] = feed

        #expect(UpdaterSuppression.reason(infoDictionary: info, isDebugBuild: false, isUpdatableLocation: true) == .missingFeedURL)
    }

    @Test(arguments: [nil, ""])
    func aBuildWithoutThePublicKeyCannot(key: String?) {
        var info = release
        info["SUPublicEDKey"] = key

        #expect(UpdaterSuppression.reason(infoDictionary: info, isDebugBuild: false, isUpdatableLocation: true) == .missingPublicKey)
    }

    @Test func aCopyOutsideApplicationsMustNotTry() {
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: false, isUpdatableLocation: false) == .notUpdatableLocation)
    }
}
