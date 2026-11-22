import AppKit
import Observation
import PIDesign
import PIFoundation

/// The shortcut step: the activation shortcut as it is held right now, why there is none when
/// there is none, and the recorder (`ShortcutFieldModel`, the one Settings › General uses).
@Observable
final class WelcomeShortcutStepModel {
    /// Why no shortcut opens the panel.
    enum Absence: Equatable, Sendable {
        /// The first launch found ⌃⌥P and ⌃⌥⌘P both taken, so none was chosen.
        case defaultsTaken
        /// The user turned the shortcut off.
        case turnedOff
        /// macOS refused the one in the setting.
        case refused(Shortcut)
    }

    let field: ShortcutFieldModel

    @ObservationIgnored private let activation: ActivationShortcut
    @ObservationIgnored private let config: ConfigStore

    #if DEBUG
    /// The debug tour shows the step as on a Mac where both defaults are taken.
    var debugSimulatesNoShortcut = false
    #endif

    init(activation: ActivationShortcut, config: ConfigStore, field: ShortcutFieldModel) {
        self.activation = activation
        self.config = config
        self.field = field
    }

    /// The shortcut that opens the panel right now.
    var shortcut: Shortcut? {
        #if DEBUG
        if debugSimulatesNoShortcut { return nil }
        #endif
        return activation.registered
    }

    /// One cap per modifier, then the key as the keyboard layout in use labels it.
    var caps: [String] { shortcut?.keyCaps ?? [] }

    /// The caps as drawn on the step, a modifier with its name.
    var heroCaps: [WelcomeHeroCap] {
        caps.map { WelcomeHeroCap(glyph: $0, word: WelcomeSpokenKeys.capWord(forGlyph: $0)) }
    }

    /// "⌃⌥P", for running text.
    var compact: String { caps.joined() }

    /// "Control Option P", for VoiceOver.
    var spoken: String {
        guard let shortcut, let key = caps.last else { return "" }
        return WelcomeSpokenKeys.words(modifiers: shortcut.modifiers, key: key)
    }

    var absence: Absence? {
        guard shortcut == nil else { return nil }
        #if DEBUG
        if debugSimulatesNoShortcut { return .defaultsTaken }
        #endif
        if let configured = activation.configured { return .refused(configured) }
        return config.isSet(.activationShortcut) ? .turnedOff : .defaultsTaken
    }

    /// What the step says when there is no shortcut.
    var absenceText: String? {
        switch absence {
        case nil:
            return nil
        case .defaultsTaken:
            let defaults = [ActivationShortcutDefaults.primary, ActivationShortcutDefaults.fallback].map { $0.keyCaps.joined() }
            return OnboardingStrings.text("welcome.shortcut.none.taken", defaults[0], defaults[1])
        case .turnedOff:
            return OnboardingStrings.text("welcome.shortcut.none.off")
        case .refused(let shortcut):
            return OnboardingStrings.text("welcome.shortcut.none.refused", shortcut.keyCaps.joined())
        }
    }

    var isRecording: Bool { field.isRecording }

    /// Leaving the step (or the window) ends a recording, which would otherwise keep the hot
    /// keys paused.
    func cancelRecording() {
        field.recorder.cancel()
    }
}

/// Key caps as VoiceOver should read them: "Control Option P", "Command K", "Return".
nonisolated enum WelcomeSpokenKeys {
    static func words(for chord: KeyChord) -> String {
        words(modifiers: chord.modifiers.eventModifierFlags, key: ShortcutGlyphFormatter.keyGlyph(chord.key))
    }

    /// - Parameter key: A key's cap ("P", "↩", "Esc"); named keys are read by name.
    static func words(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append(OnboardingStrings.text("welcome.spoken.control")) }
        if modifiers.contains(.option) { parts.append(OnboardingStrings.text("welcome.spoken.option")) }
        if modifiers.contains(.shift) { parts.append(OnboardingStrings.text("welcome.spoken.shift")) }
        if modifiers.contains(.command) { parts.append(OnboardingStrings.text("welcome.spoken.command")) }
        parts.append(name(ofCap: key))
        return parts.joined(separator: " ")
    }

    /// What a Mac keyboard prints on a modifier key under its symbol ("control"); nil for any
    /// other key.
    static func capWord(forGlyph glyph: String) -> String? {
        switch glyph {
        case "⌃": OnboardingStrings.text("welcome.cap.control")
        case "⌥": OnboardingStrings.text("welcome.cap.option")
        case "⇧": OnboardingStrings.text("welcome.cap.shift")
        case "⌘": OnboardingStrings.text("welcome.cap.command")
        default: nil
        }
    }

    /// The name of a named key's cap; any other cap (a letter, a digit, a bracket) is read as it is.
    static func name(ofCap cap: String) -> String {
        switch cap {
        case "↩", "⌤": OnboardingStrings.text("welcome.spoken.return")
        case "Esc": OnboardingStrings.text("welcome.spoken.escape")
        case "⇥": OnboardingStrings.text("welcome.spoken.tab")
        case "⌫", "⌦": OnboardingStrings.text("welcome.spoken.delete")
        case "Space", "␣": OnboardingStrings.text("welcome.spoken.space")
        case "↑": OnboardingStrings.text("welcome.spoken.up")
        case "↓": OnboardingStrings.text("welcome.spoken.down")
        case "←": OnboardingStrings.text("welcome.spoken.left")
        case "→": OnboardingStrings.text("welcome.spoken.right")
        default: cap
        }
    }
}

/// One large key cap of the shortcut step: its symbol and, for a modifier, its name.
nonisolated struct WelcomeHeroCap: Hashable, Sendable {
    let glyph: String
    let word: String?
}
