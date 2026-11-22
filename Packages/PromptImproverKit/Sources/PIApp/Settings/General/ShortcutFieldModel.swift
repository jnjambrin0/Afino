import AppKit
import Observation

/// The "Open Afino" recorder in Settings › General and in the welcome's shortcut step: records
/// with `ShortcutRecorder`, checks that no other app holds the combination, and registers it
/// through `ActivationShortcut`.
@Observable
final class ShortcutFieldModel {
    /// Why the last recording did not change anything.
    enum Warning: Equatable, Sendable {
        case conflict(ShortcutConflict)
        /// Another app holds the combination as its hot key.
        case usedByAnotherApp
        /// macOS refused to register it.
        case notRegistered

        var text: String {
            switch self {
            case .conflict(.usedBySystem):
                SettingsStrings.text("settings.shortcut.conflict.system")
            case .conflict(.usedByMenuItem(let title)):
                SettingsStrings.text("settings.shortcut.conflict.menu", title)
            case .conflict(.usedByShortcut(let name)):
                SettingsStrings.text("settings.shortcut.conflict.shortcut", name)
            case .usedByAnotherApp:
                SettingsStrings.text("settings.shortcut.conflict.app")
            case .notRegistered:
                SettingsStrings.text("settings.shortcut.notRegistered")
            }
        }
    }

    let recorder: ShortcutRecorder
    private(set) var warning: Warning?

    @ObservationIgnored private let activation: ActivationShortcut
    @ObservationIgnored private let isAvailable: (Shortcut) -> Bool

    /// - Parameter isAvailable: Whether no other app holds a combination as its hot key.
    init(activation: ActivationShortcut, recorder: ShortcutRecorder, isAvailable: @escaping (Shortcut) -> Bool) {
        self.activation = activation
        self.recorder = recorder
        self.isAvailable = isAvailable
    }

    /// The shortcut that opens the panel right now.
    var shortcut: Shortcut? { activation.registered }

    var isRecording: Bool { recorder.isRecording }

    /// The warning under the field: a conflict the recorder found, or one found afterwards.
    var displayedWarning: Warning? {
        recorder.conflict.map(Warning.conflict) ?? warning
    }

    /// The caps the field shows: the modifiers held while recording, else the shortcut.
    var caps: [String] {
        if recorder.isRecording {
            return ShortcutDisplay.modifierGlyphs(recorder.heldModifiers).map(String.init)
        }
        return shortcut?.keyCaps ?? []
    }

    /// The shortcut as VoiceOver reads it.
    var spokenShortcut: String {
        shortcut.map { ShortcutDisplay.string(for: $0, spaceKeyName: SettingsStrings.text("settings.shortcut.space")) }
            ?? SettingsStrings.text("settings.shortcut.none")
    }

    func toggleRecording() {
        if recorder.isRecording {
            recorder.cancel()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        warning = nil
        recorder.conflict = nil
        ShortcutRecorder.announce(SettingsStrings.text("settings.shortcut.announce.recording"))
        // This is Afino's only global shortcut: none of its own can clash with it.
        recorder.start(otherShortcuts: []) { [weak self] ending in
            self?.finish(ending)
        }
    }

    /// Turns the shortcut off; the panel stays reachable from the menu bar.
    func clear() {
        recorder.cancel()
        warning = nil
        recorder.conflict = nil
        activation.change(to: nil)
        ShortcutRecorder.announce(SettingsStrings.text("settings.shortcut.announce.cleared"))
    }

    private func finish(_ ending: ShortcutRecorder.Ending) {
        switch ending {
        case .recorded(let shortcut):
            apply(shortcut)
        case .cleared:
            activation.change(to: nil)
            ShortcutRecorder.announce(SettingsStrings.text("settings.shortcut.announce.cleared"))
        case .cancelled:
            // When a conflict is the reason, the recorder sets `recorder.conflict` right after,
            // and `displayedWarning` shows it.
            break
        }
    }

    private func apply(_ shortcut: Shortcut) {
        let previous = activation.registered
        guard shortcut != previous else { return }
        guard isAvailable(shortcut) else {
            warning = .usedByAnotherApp
            return
        }
        activation.change(to: shortcut)
        guard activation.registered == shortcut else {
            // Keep the setting on the shortcut that still works, so the next launch has it too.
            activation.change(to: previous)
            warning = .notRegistered
            return
        }
        ShortcutRecorder.announce(SettingsStrings.text("settings.shortcut.announce.recorded", spokenShortcut))
    }
}
