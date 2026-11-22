import CoreGraphics
import Foundation
import Observation
import PICore
import PIDesign
import PIProviders

/// Which floating card is open.
nonisolated enum PanelMenuKind: Hashable, Sendable {
    /// ⌘K.
    case actions
    /// The target chip's "Write the prompt for".
    case target
}

/// Where the add-a-key card is in its flow.
nonisolated enum SetupStatus: Hashable, Sendable {
    case idle
    case checking
    /// The provider accepted the key; the panel moves on in a moment.
    case accepted
    /// Saved without a check (offline, or the key may not list models); the panel moves on.
    case unverified
    case rejected
    case wrongProvider(ProviderID)
    case storeFailed
    case empty

    /// The card stays up whatever the vault says (a key being checked already counts as usable).
    var holdsCard: Bool {
        switch self {
        case .checking, .accepted, .unverified: true
        case .idle, .rejected, .wrongProvider, .storeFailed, .empty: false
        }
    }
}

/// The ⌘Y list.
struct PanelHistoryState {
    var entries: [HistoryEntry] = []
    var filter = ""
    var selectedID: HistoryEntry.ID?
    /// The entry just deleted, while its undo toast is up.
    var deleted: HistoryEntry?
    /// Whether `entries` has been read from the store since the list opened.
    var isLoaded = false

    var visible: [HistoryEntry] {
        HistoryRowFormatter.filter(entries, query: filter)
    }

    var selectedIndex: Int? {
        selectedID.flatMap { id in visible.firstIndex { $0.id == id } }
    }
}

/// The panel's own state: what is not the session's (the session is the single source of truth
/// for the prompt, its runs and its versions). Views read it; only `PanelController` changes it.
@Observable
final class PanelModel {
    var overlay: PanelOverlay = .none
    /// The add-a-key card, once up, stays until its flow ends (a key being checked already counts
    /// as usable, which would otherwise take the card away mid-check).
    var isSetupLatched = false

    var isOriginalExpanded = false
    /// The origin row's measured height: 40, more while the original is expanded.
    var headerHeight: CGFloat = EmberDesign.Panel.headerHeight
    /// Mirrors the refine field.
    var refineText = ""
    /// The compose input shows a draft recalled with ↑.
    var showsRecalledDraft = false

    var openMenu: PanelMenuKind?
    var highlightedMenuItemID: String?

    /// The panel is shrinking into the "Copied" pill.
    var isConfirmingCopy = false
    var isFullKeyboardAccessEnabled = false

    /// Where the target chip and the ⌘K hint are, in the panel's content (top-left origin), so
    /// their cards open next to them.
    var targetChipFrame: CGRect = .zero
    var actionsHintFrame: CGRect = .zero

    var history = PanelHistoryState()

    var setupKeyText = ""
    var setupStatus: SetupStatus = .idle
    var isKeyFieldFocused = false

    /// Clears what belongs to one showing of the panel.
    func resetTransientState() {
        openMenu = nil
        highlightedMenuItemID = nil
        if overlay == .history { overlay = .none }
        history.deleted = nil
    }
}
