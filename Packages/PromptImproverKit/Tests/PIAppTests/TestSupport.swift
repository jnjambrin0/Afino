import Foundation

/// A `UserDefaults` suite of its own for one test, removed when the test is done.
nonisolated final class EphemeralDefaults {
    let suiteName = "PIAppTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
