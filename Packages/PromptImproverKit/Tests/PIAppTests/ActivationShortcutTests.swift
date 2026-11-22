import AppKit
import Carbon.HIToolbox
@testable import PIApp
import PIFoundation
import Testing

/// The activation shortcut a launch chooses and keeps.
struct ActivationShortcutTests {
    private let ephemeral = EphemeralDefaults()
    private var config: ConfigStore { ConfigStore(defaults: ephemeral.defaults) }

    @Test func theDefaultsAreControlOptionPThenControlOptionCommandP() {
        #expect(ActivationShortcutDefaults.primary == Shortcut(keyCode: kVK_ANSI_P, modifiers: [.control, .option]))
        #expect(ActivationShortcutDefaults.fallback == Shortcut(keyCode: kVK_ANSI_P, modifiers: [.control, .option, .command]))
    }

    @Test func aFirstLaunchTakesControlOptionPWhenItIsFree() {
        let chosen = ActivationShortcutDefaults.applyInitialChoice(to: config) { _ in true }

        #expect(chosen == ActivationShortcutDefaults.primary)
        #expect(config.value(for: .activationShortcut).value == ActivationShortcutDefaults.primary)
    }

    @Test func aFirstLaunchFallsBackWhenSomethingElseHasControlOptionP() {
        let chosen = ActivationShortcutDefaults.applyInitialChoice(to: config) { $0 != ActivationShortcutDefaults.primary }

        #expect(chosen == ActivationShortcutDefaults.fallback)
        #expect(config.value(for: .activationShortcut).value == ActivationShortcutDefaults.fallback)
    }

    @Test func whenBothAreTakenNothingIsStoredAndTheNextLaunchLooksAgain() {
        let config = config

        #expect(ActivationShortcutDefaults.applyInitialChoice(to: config) { _ in false } == nil)
        #expect(!config.isSet(.activationShortcut))

        #expect(ActivationShortcutDefaults.applyInitialChoice(to: config) { _ in true } == ActivationShortcutDefaults.primary)
    }

    @Test func aStoredShortcutIsNeverReplaced() {
        let config = config
        let mine = Shortcut(keyCode: kVK_F13, modifiers: [])
        config.set(JSONConfigValue(mine), for: .activationShortcut)
        var asked = false

        let chosen = ActivationShortcutDefaults.applyInitialChoice(to: config) { _ in
            asked = true
            return true
        }

        #expect(chosen == nil)
        #expect(!asked)
        #expect(config.value(for: .activationShortcut).value == mine)
    }

    @Test func aShortcutTurnedOffStaysOff() {
        let config = config
        config.set(JSONConfigValue(nil), for: .activationShortcut)

        #expect(ActivationShortcutDefaults.applyInitialChoice(to: config) { _ in true } == nil)
        #expect(config.isSet(.activationShortcut))
        #expect(config.value(for: .activationShortcut).value == nil)
    }

    @Test func theShortcutIsStoredAsJSONWithKeyCodeAndModifiers() throws {
        let defaults = ephemeral.defaults
        ConfigStore(defaults: defaults).set(JSONConfigValue(ActivationShortcutDefaults.primary), for: .activationShortcut)

        let data = try #require(defaults.data(forKey: "activationShortcut"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["keyCode"] as? Int == kVK_ANSI_P)
        #expect(object["internalModifiers"] as? UInt == NSEvent.ModifierFlags([.control, .option]).rawValue)
    }
}
