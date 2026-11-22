import AppKit
import Carbon.HIToolbox
import Observation
import os
import PIFoundation

/// A shortcut setting, stored as JSON data holding `keyCode` and `internalModifiers`.
typealias ShortcutKey = ConfigKey<JSONConfigValue<Shortcut?>>

extension ConfigKey where Value == JSONConfigValue<Shortcut?> {
    /// Opens and closes the panel, system-wide. Nothing stored: no launch has chosen one yet.
    /// A stored `null`: the user turned the shortcut off.
    nonisolated static var activationShortcut: ShortcutKey { ConfigKey("activationShortcut", default: JSONConfigValue(nil)) }
}

/// The shortcuts the activation shortcut starts from.
nonisolated enum ActivationShortcutDefaults {
    /// ⌃⌥P. (I for "improve" was ruled out: Rectangle uses ⌃⌥I, and ⌘⌥I opens browsers' developer
    /// tools.)
    static let primary = Shortcut(keyCode: kVK_ANSI_P, modifiers: [.control, .option])
    /// ⌃⌥⌘P, for a Mac where something else already answers to ⌃⌥P.
    static let fallback = Shortcut(keyCode: kVK_ANSI_P, modifiers: [.control, .option, .command])

    /// The first of `primary` and `fallback` nothing else answers to; nil when both are taken.
    static func initialChoice(isAvailable: (Shortcut) -> Bool) -> Shortcut? {
        [primary, fallback].first(where: isAvailable)
    }

    /// Runs at every launch before registering: the first launch that finds a free shortcut
    /// stores it. A stored value (a shortcut, or none because the user turned it off) is never
    /// touched. When both defaults are taken nothing is stored, so the next launch looks again.
    ///
    /// - Returns: The shortcut chosen now, if this launch chose one.
    @discardableResult
    static func applyInitialChoice(to config: ConfigStore, isAvailable: (Shortcut) -> Bool) -> Shortcut? {
        guard !config.isSet(.activationShortcut),
              let choice = initialChoice(isAvailable: isAvailable)
        else { return nil }
        config.set(JSONConfigValue(choice), for: .activationShortcut)
        return choice
    }
}

/// The system-wide shortcut that toggles the panel: chosen on the first launch, kept in
/// settings, and held as a Carbon hot key while the app runs.
@MainActor
@Observable
final class ActivationShortcut {
    private static let caller = "activation"

    /// The shortcut held as a hot key right now. Nil when there is none: the user turned it off,
    /// both defaults were taken, or the system refused the registration.
    private(set) var registered: Shortcut?

    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let hotKeys: HotKeyCenter
    @ObservationIgnored private var action: (@MainActor () -> Void)?
    @ObservationIgnored private let log = Log.logger(.shortcut)

    init(config: ConfigStore, hotKeys: HotKeyCenter) {
        self.config = config
        self.hotKeys = hotKeys
    }

    /// What the setting holds.
    var configured: Shortcut? {
        config.value(for: .activationShortcut).value
    }

    /// Chooses the shortcut on the first launch, then registers it. Called once the main menu is
    /// installed, so that its key equivalents count as taken.
    func start(action: @escaping @MainActor () -> Void) {
        self.action = action
        let system = ShortcutValidator.current()
        let chosen = ActivationShortcutDefaults.applyInitialChoice(to: config) { [hotKeys] shortcut in
            system.conflict(for: shortcut, key: ShortcutValidator.key(forKeyCode: shortcut.keyCode)) == nil
                && hotKeys.isAvailable(shortcut)
        }
        if let chosen {
            log.notice("Activation shortcut chosen on first launch: \(ShortcutDisplay.string(for: chosen), privacy: .public)")
        } else if !config.isSet(.activationShortcut) {
            log.error("Activation shortcut: ⌃⌥P and ⌃⌥⌘P are both taken; none registered")
        }
        registerConfigured()
    }

    /// Makes `shortcut` the activation shortcut (from the recorder); nil turns it off.
    func change(to shortcut: Shortcut?) {
        config.set(JSONConfigValue(shortcut), for: .activationShortcut)
        registerConfigured()
    }

    private func registerConfigured() {
        guard let action else { return }
        guard let shortcut = configured else {
            hotKeys.unregister(caller: Self.caller)
            registered = nil
            return
        }
        // A refused registration leaves the previous hot key, if any, in place.
        if hotKeys.register(shortcut, caller: Self.caller, action: action) {
            registered = shortcut
            log.notice("Activation shortcut registered: \(ShortcutDisplay.string(for: shortcut), privacy: .public)")
        } else {
            log.error("Activation shortcut \(ShortcutDisplay.string(for: shortcut), privacy: .public) could not be registered")
        }
    }
}
