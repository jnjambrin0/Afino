#if DEBUG
import Foundation
import Observation
import PICore
import PIProviders

/// Debug builds only: launch flags for looking at the welcome without resetting the app to a
/// first launch. Pass them through `scripts/run.sh`, for example
/// `scripts/run.sh --welcome key --welcome-language es --in-memory-secrets`.
///
/// - `--welcome <step>`: opens the welcome at that step (`1`–`4`, or `welcome`, `key`,
///   `shortcut`, `keys`), whatever `onboardingCompleted` says.
/// - `--welcome-language <code>`: the welcome, and the Settings controls it reuses, in that
///   language (`es`, `en`). `-AppleLanguages "(es)"` does the same for the whole app.
/// - `--welcome-tour <directory>`: from the step given (or the first), shows every step and state
///   in turn (the key rejected and accepted against a stand-in vault, the shortcut tried, no
///   shortcut) without activating the app, and writes the name of each state to
///   `<directory>/state` as it shows, so a screenshot script can tell when to capture.
///
/// With `--in-memory-secrets` nothing touches the Keychain.
struct WelcomeDebugOptions {
    let step: WelcomeStep?
    let language: String?
    let tourMarkerDirectory: URL?

    var isTour: Bool { tourMarkerDirectory != nil }

    init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        language = value("--welcome-language")
        tourMarkerDirectory = value("--welcome-tour").map { URL(filePath: $0, directoryHint: .isDirectory) }
        let requested = value("--welcome").flatMap(Self.step(named:))
        step = requested ?? (tourMarkerDirectory != nil ? .welcome : nil)
    }

    private static func step(named name: String) -> WelcomeStep? {
        switch name.lowercased() {
        case "1", "welcome": .welcome
        case "2", "key", "apikey": .apiKey
        case "3", "shortcut": .shortcut
        case "4", "keys": .keys
        default: nil
        }
    }

    /// Points the welcome's and Settings' string lookups at `--welcome-language`, if given.
    func applyLanguage() {
        guard let language else { return }
        OnboardingStrings.previewLanguage = language
        SettingsStrings.previewLanguage = language
    }
}

/// `--welcome-tour`: plays every step and state for screenshots, a few seconds each.
@MainActor
final class WelcomeTour {
    private let markerDirectory: URL?
    private let vault: WelcomeTourVault?

    init(markerDirectory: URL?, vault: WelcomeTourVault?) {
        self.markerDirectory = markerDirectory
        self.vault = vault
    }

    func run(_ controller: WelcomeWindowController) {
        let flow = controller.flow
        let (keyStep, shortcutStep) = controller.tourModels
        Task { @MainActor in
            // The illustration: thinking, then the end once it has played.
            mark("1-welcome-thinking")
            try? await Task.sleep(for: .seconds(4.6))
            mark("1-welcome")
            try? await Task.sleep(for: .seconds(1.8))

            flow.debugShow(.apiKey)
            mark("2-key-empty")
            try? await Task.sleep(for: .seconds(2.2))
            vault?.saveOutcome = .rejected
            keyStep.entry.draft = "sk-ant-api03-not-a-real-key-0000"
            await keyStep.entry.save()
            mark("2-key-rejected")
            try? await Task.sleep(for: .seconds(2.2))
            vault?.saveOutcome = .valid
            keyStep.entry.draft = "sk-ant-api03-a-working-key-a1b2"
            await keyStep.entry.save()
            mark("2-key-ready")
            try? await Task.sleep(for: .seconds(2.2))

            flow.debugShow(.shortcut)
            mark("3-shortcut")
            try? await Task.sleep(for: .seconds(2.2))
            flow.debugShow(.shortcut, triedShortcut: true)
            mark("3-shortcut-tried")
            try? await Task.sleep(for: .seconds(2.2))
            shortcutStep.debugSimulatesNoShortcut = true
            flow.debugShow(.shortcut)
            mark("3-shortcut-none")
            try? await Task.sleep(for: .seconds(2.2))
            shortcutStep.debugSimulatesNoShortcut = false

            flow.debugShow(.keys)
            mark("4-keys")
            try? await Task.sleep(for: .seconds(2.2))
            mark("done")
        }
    }

    private func mark(_ state: String) {
        guard let markerDirectory else { return }
        try? FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        try? Data(state.utf8).write(to: markerDirectory.appending(path: "state"), options: .atomic)
    }
}

/// A vault that answers with the outcome the tour picks; never the Keychain, never the network.
@Observable
final class WelcomeTourVault: KeyVaulting {
    private var states: [ProviderID: KeyState] = [:]
    @ObservationIgnored var saveOutcome: KeyCheckOutcome = .valid

    func state(for provider: ProviderID) -> KeyState {
        states[provider] ?? .missing
    }

    func save(_ rawKey: String, for provider: ProviderID) async -> KeyCheckOutcome {
        let key = APIKey(rawKey)
        let previous = states[provider]
        states[provider] = .checking(masked: key.masked)
        try? await Task.sleep(for: .milliseconds(400))
        switch saveOutcome {
        case .valid: states[provider] = .valid(masked: key.masked)
        case .savedUnverified, .savedWithLimitedAccess: states[provider] = .unverified(masked: key.masked)
        case .rejected, .wrongProvider, .empty, .storeFailed: states[provider] = previous
        }
        return saveOutcome
    }

    func recheck(_ provider: ProviderID) async -> KeyCheckOutcome {
        saveOutcome
    }

    func remove(_ provider: ProviderID) {
        states[provider] = .missing
    }
}
#endif
