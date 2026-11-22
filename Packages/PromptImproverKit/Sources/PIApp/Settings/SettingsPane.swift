import Observation
import PIFoundation

/// The Settings panes, in sidebar order: everyday choices first, then the engine and its keys,
/// the user's own instructions, the keyboard reference, and the app itself.
enum SettingsPane: String, CaseIterable, Sendable {
    case general
    case engine
    case instructions
    case shortcuts
    case about

    /// The sidebar name, which is also the pane's large title and the window title.
    var title: String {
        switch self {
        case .general: SettingsStrings.text("settings.pane.general")
        case .engine: SettingsStrings.text("settings.pane.engine")
        case .instructions: SettingsStrings.text("settings.pane.instructions")
        case .shortcuts: SettingsStrings.text("settings.pane.shortcuts")
        case .about: SettingsStrings.text("settings.pane.about")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .engine: "cpu"
        case .instructions: "text.quote"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }
}

extension ConfigKey where Value == String {
    /// The pane Settings showed last, opened again next time.
    static let settingsSelectedPane = ConfigKey("settingsSelectedPane", default: SettingsPane.general.rawValue)
}

/// Which pane Settings shows, what the Shortcuts pane lists, and the dialog on screen. Shared by
/// the window controller (which titles the window after the pane) and the SwiftUI content.
@Observable
final class SettingsWindowModel {
    var selectedPane: SettingsPane {
        didSet { config.set(selectedPane.rawValue, for: .settingsSelectedPane) }
    }

    /// The panel's keyboard shortcuts, for the Shortcuts pane.
    var shortcutReference: [ShortcutReferenceGroup]

    /// The confirmation on screen, drawn over the whole window.
    var dialog: SettingsDialog?

    @ObservationIgnored private let config: ConfigStore

    init(config: ConfigStore, shortcutReference: [ShortcutReferenceGroup] = []) {
        self.config = config
        self.shortcutReference = shortcutReference
        selectedPane = SettingsPane(rawValue: config.value(for: .settingsSelectedPane)) ?? .general
    }
}

/// A confirmation or a notice shown with `EDialog` over the Settings window.
struct SettingsDialog {
    struct Action {
        enum Role {
            case cancel
            case confirm
            case destructive
        }

        let title: String
        let role: Role
        /// Runs after the dialog has been dismissed.
        let action: () -> Void
    }

    let title: String
    var message: String?
    var symbol: String?
    let actions: [Action]
}
