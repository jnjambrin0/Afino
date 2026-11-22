import AppKit

/// Process entry point. The app target is a shell whose `main.swift` only calls
/// `PromptImproverApplication.main()`.
///
/// The app is called Afino; it was called PromptImprover before 1.0. Identifiers that users or
/// tooling already depend on keep the old name on purpose, and are not renamed: this type, the
/// `PromptImproverKit` package, the bundle identifier `com.jnjambrin0.PromptImprover` (which
/// carries the Keychain items, the preferences and the login item), and a few internal names
/// such as the Settings window's saved frame.
public enum PromptImproverApplication {
    private static let delegate = AppDelegate()

    public static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        // Afino is a menu bar app (LSUIElement): no Dock icon, except while the welcome is up.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
