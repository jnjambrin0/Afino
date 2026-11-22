import PICore

/// What the menu bar icon shows.
enum StatusIconState: Equatable, Sendable {
    /// The glyph, at rest.
    case idle
    /// A run is in flight: the glyph breathes (a dot under Reduce Motion).
    case running
    /// A run finished while the panel was hidden: a checkmark for a moment.
    case done
    /// Something needs the user: a dot on the glyph.
    case attention(Attention)

    enum Attention: Equatable, Sendable {
        /// A run failed while the panel was hidden.
        case runFailed
        /// The chosen provider has no key that can be used.
        case noUsableKey
    }
}

/// Derives the icon from the session's phase changes, whether the panel is on screen, and the
/// key. A value type changed only by its methods, so every transition is testable without a
/// status item or a clock.
struct StatusIconTracker: Equatable, Sendable {
    /// A run completed while the panel was hidden; cleared when the check's time is up, a new run
    /// starts, or the panel opens.
    private(set) var showsDone = false
    /// A run failed while the panel was hidden; cleared when the panel next opens or a run
    /// completes.
    private(set) var failedWhileHidden = false

    /// Records a change of the session's phase.
    ///
    /// - Returns: Whether the checkmark just appeared, so the owner starts its timer.
    @discardableResult
    mutating func phaseChanged(from old: SessionState.Phase, to new: SessionState.Phase, isPanelVisible: Bool) -> Bool {
        switch (Self.isRunning(old), new) {
        case (false, .running):
            showsDone = false
            return false
        case (true, .result):
            failedWhileHidden = false
            guard !isPanelVisible else { return false }
            showsDone = true
            return true
        case (_, .failed):
            if case .failed = old { return false }
            if !isPanelVisible {
                failedWhileHidden = true
                showsDone = false
            }
            return false
        default:
            return false
        }
    }

    /// The panel came on screen: the user has seen whatever happened.
    mutating func panelDidOpen() {
        showsDone = false
        failedWhileHidden = false
    }

    /// The checkmark's time is up.
    mutating func doneExpired() {
        showsDone = false
    }

    /// The icon for the current phase. A run in flight wins; then the checkmark; then anything
    /// that needs attention.
    func state(phase: SessionState.Phase, hasUsableKey: Bool) -> StatusIconState {
        if Self.isRunning(phase) { return .running }
        if showsDone { return .done }
        if failedWhileHidden { return .attention(.runFailed) }
        if !hasUsableKey { return .attention(.noUsableKey) }
        return .idle
    }

    private static func isRunning(_ phase: SessionState.Phase) -> Bool {
        if case .running = phase { return true }
        return false
    }
}

/// How each icon state is drawn: whether the glyph breathes and whether it carries a dot.
struct StatusIconAppearance: Equatable, Sendable {
    enum Glyph: Equatable, Sendable {
        case cursor
        case checkmark
    }

    let glyph: Glyph
    let hasDot: Bool
    let breathes: Bool

    init(_ state: StatusIconState, reduceMotion: Bool) {
        switch state {
        case .idle:
            self.init(glyph: .cursor, hasDot: false, breathes: false)
        case .running:
            self.init(glyph: .cursor, hasDot: reduceMotion, breathes: !reduceMotion)
        case .done:
            self.init(glyph: .checkmark, hasDot: false, breathes: false)
        case .attention:
            self.init(glyph: .cursor, hasDot: true, breathes: false)
        }
    }

    init(glyph: Glyph, hasDot: Bool, breathes: Bool) {
        self.glyph = glyph
        self.hasDot = hasDot
        self.breathes = breathes
    }
}
