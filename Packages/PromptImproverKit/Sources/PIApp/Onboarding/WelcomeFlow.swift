import Observation
import PICore

/// The four steps of the welcome, in order.
nonisolated enum WelcomeStep: Int, CaseIterable, Comparable, Sendable {
    /// What Afino is, with the illustrated panel.
    case welcome
    /// The user's API key.
    case apiKey
    /// The shortcut that opens the panel from any app; the user tries it here.
    case shortcut
    /// The keys that work in the panel.
    case keys

    static func < (lhs: WelcomeStep, rhs: WelcomeStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 1-based, for "Step 2 of 4".
    var number: Int { rawValue + 1 }

    var next: WelcomeStep? { WelcomeStep(rawValue: rawValue + 1) }
    var previous: WelcomeStep? { WelcomeStep(rawValue: rawValue - 1) }

    var title: String {
        switch self {
        case .welcome: OnboardingStrings.text("welcome.intro.title")
        case .apiKey: OnboardingStrings.text("welcome.key.title")
        case .shortcut: OnboardingStrings.text("welcome.shortcut.title")
        case .keys: OnboardingStrings.text("welcome.keys.title")
        }
    }

    /// "Step 2 of 4".
    var progress: String {
        OnboardingStrings.text("welcome.progress", number, WelcomeStep.allCases.count)
    }

    /// What VoiceOver says when the step comes in: its title, then where it is.
    var announcement: String {
        OnboardingStrings.text("welcome.announce", title, number, WelcomeStep.allCases.count)
    }

    /// Whether the step's button (the one Return presses) can be pressed now. The key step
    /// waits for a key that works ("Add it later" is the way on without one); the shortcut step
    /// waits while a new shortcut is being recorded, so Return cannot move on in the middle of it.
    func isPrimaryEnabled(keyStepCanContinue: Bool, isRecordingShortcut: Bool) -> Bool {
        switch self {
        case .welcome, .keys: true
        case .apiKey: keyStepCanContinue
        case .shortcut: !isRecordingShortcut
        }
    }
}

/// The welcome's state machine: which step shows, which way the last move went, whether the
/// user has tried the shortcut, and how the window is left. Leaving in any way — Start, Skip,
/// Esc, ⌘W — marks onboarding completed (the panel's add-a-key card still covers a user who
/// skipped the key); only Start goes on to the panel.
@Observable
final class WelcomeFlow {
    enum Direction: Equatable, Sendable {
        case forward
        case backward
    }

    enum Exit: Equatable, Sendable {
        /// Start, on the last step: the panel opens next.
        case finished
        /// Skip, Esc or ⌘W, on any step.
        case skipped
    }

    private(set) var step: WelcomeStep = .welcome {
        didSet {
            if step != oldValue { onStepChange?(oldValue, step) }
        }
    }
    /// Which way the last step change went: steps slide in from that side.
    private(set) var direction: Direction = .forward
    /// The window is on screen. The activation shortcut is only claimed while it is.
    private(set) var isPresented = false
    /// How many times the activation shortcut was pressed while the shortcut step showed.
    private(set) var shortcutPressCount = 0
    /// The illustration on the first step animates once per showing; back on it, it stays still.
    var hasPlayedIllustration = false

    /// Called once per showing, when it ends.
    @ObservationIgnored var onExit: ((Exit) -> Void)?
    /// Called with the step left and the step shown, whenever the step changes.
    @ObservationIgnored var onStepChange: ((WelcomeStep, WelcomeStep) -> Void)?
    @ObservationIgnored private let settings: SettingsModel

    init(settings: SettingsModel) {
        self.settings = settings
    }

    /// The user pressed the activation shortcut on the shortcut step: it works.
    var hasTriedShortcut: Bool { shortcutPressCount > 0 }

    var isFirstStep: Bool { step.previous == nil }
    var isLastStep: Bool { step.next == nil }

    /// A new showing, from `step` (the first, unless a debug flag asks for another).
    func present(at step: WelcomeStep = .welcome) {
        self.step = step
        direction = .forward
        shortcutPressCount = 0
        hasPlayedIllustration = false
        isPresented = true
    }

    /// Continue; Start on the last step.
    func advance() {
        guard isPresented else { return }
        guard let next = step.next else {
            leave(.finished)
            return
        }
        direction = .forward
        step = next
    }

    /// Back one step; nothing on the first.
    func back() {
        guard isPresented, let previous = step.previous else { return }
        direction = .backward
        step = previous
    }

    /// Skip, Esc or ⌘W.
    func skip() {
        leave(.skipped)
    }

    /// The activation shortcut was pressed. On the shortcut step that is the user trying it: it
    /// is celebrated in place instead of opening the panel. Returns whether it was claimed;
    /// otherwise the caller toggles the panel as usual.
    func activationShortcutPressed() -> Bool {
        guard isPresented, step == .shortcut else { return false }
        shortcutPressCount += 1
        return true
    }

    /// A new shortcut was recorded: it has not been tried yet.
    func shortcutDidChange() {
        shortcutPressCount = 0
    }

    private func leave(_ exit: Exit) {
        guard isPresented else { return }
        isPresented = false
        settings.onboardingCompleted = true
        onExit?(exit)
    }

    #if DEBUG
    /// The debug tour jumps between steps and states without the buttons.
    func debugShow(_ step: WelcomeStep, triedShortcut: Bool = false) {
        direction = step >= self.step ? .forward : .backward
        self.step = step
        shortcutPressCount = triedShortcut ? 1 : 0
    }
    #endif
}
