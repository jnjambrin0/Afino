import AppKit
import Observation
import PICore
import PIDesign
import PIPrompts
import PIProviders

/// The panel follows the session: the result text, the height, the focus and the VoiceOver
/// announcements all react to `session.state`, whether the change came from a key or from a run
/// streaming in the background.
extension PanelController {
    // MARK: Observing

    /// Re-arms itself after every change; changes in one turn arrive together.
    func startObservingSession() {
        withObservationTracking {
            _ = session.state
            _ = session.hasUsableKey
            _ = settings.historyEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshFromSession()
                startObservingSession()
            }
        }
    }

    /// Brings everything the panel derives from the session up to date. Idempotent: called after
    /// every session call the panel makes, and again by the observation.
    func refreshFromSession() {
        let state = session.state
        let previous = lastState
        guard previous != state || lastScreen == nil || lastScreen != screen || needsSetupLatchUpdate else { return }
        lastState = state
        updateSetupLatch()
        input.setDraft(state.draft)
        syncStream(from: previous, to: state)
        if let previous { announceTransition(from: previous, to: state) }

        let screen = screen
        let screenChanged = lastScreen != screen
        let oldScreen = lastScreen
        lastScreen = screen
        if screenChanged {
            screenDidChange(from: oldScreen, to: screen)
        } else if previous?.phase != state.phase, !state.isRunning {
            // Failed → failed with another problem. A run's own stages (connecting → thinking →
            // writing) never resize the panel: while it runs the height only follows the text.
            updateHeight(.screen)
        }
    }

    private var needsSetupLatchUpdate: Bool {
        model.isSetupLatched != shouldLatchSetup
    }

    private var shouldLatchSetup: Bool {
        if session.state.phase == .composing, !session.hasUsableKey { return true }
        return model.isSetupLatched && (!session.hasUsableKey || model.setupStatus.holdsCard)
    }

    /// The add-a-key card replaces the composer when the chosen provider has no usable key, and
    /// stays until its own flow ends: a key being checked already counts as usable.
    func updateSetupLatch() {
        let latch = shouldLatchSetup
        guard model.isSetupLatched != latch else { return }
        model.isSetupLatched = latch
        if !latch, !model.setupStatus.holdsCard {
            model.setupStatus = .idle
        }
    }

    private func screenDidChange(from old: PanelScreen?, to new: PanelScreen) {
        // A card belongs to the screen it was opened on.
        if model.openMenu != nil { closeMenu(animated: true) }
        setInputVisible(new == .compose, animated: old != nil && isPresented)
        if new != .result {
            refineField.setText("")
            model.refineText = ""
        }
        if new == .compose || new == .setup {
            model.isOriginalExpanded = false
        }
        pendingFocus = focusTarget(for: new)
        applyPendingFocus()
        updateHeight(.screen)
    }

    /// The compose input fades with the content around it (opacity only, so Reduce Motion keeps it).
    private func setInputVisible(_ visible: Bool, animated: Bool) {
        let target: CGFloat = visible ? 1 : 0
        if visible { input.isHidden = false }
        guard animated else {
            input.alphaValue = target
            input.isHidden = !visible
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = EmberDesign.Motion.contentCrossfadeDuration
            input.animator().alphaValue = target
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !visible, self.screen != .compose else { return }
                self.input.isHidden = true
            }
        }
    }

    // MARK: The result text

    /// Feeds the result text: a breathing caret until the first text, a trailing caret while it
    /// streams, then the final text, read-only. A refinement keeps the version it starts from on
    /// screen, dimmed, until its own first text clears it.
    private func syncStream(from old: SessionState?, to state: SessionState) {
        if trackedRunID != state.runID {
            trackedRunID = state.runID
            runHasShownText = false
        }
        let wasRunning = old?.isRunning == true
        switch state.phase {
        case .composing:
            streamView.caretMode = .hidden
            streamView.isDimmed = false
            streamView.setText("", streaming: false)
        case .running:
            if state.liveText.isEmpty {
                if let shown = state.shown {
                    streamView.isDimmed = true
                    streamView.caretMode = .hidden
                    streamView.setText(shown.text, streaming: false)
                } else {
                    streamView.isDimmed = false
                    streamView.setText("", streaming: false)
                    streamView.caretMode = .breathing
                }
            } else {
                if !runHasShownText {
                    runHasShownText = true
                    streamView.isDimmed = false
                    streamView.setText("", streaming: false)
                }
                streamView.caretMode = .trailing
                streamView.setText(state.liveText, streaming: true)
            }
        case .result, .failed, .stopped:
            streamView.caretMode = .hidden
            streamView.isDimmed = false
            if wasRunning { streamView.finishStreaming() }
            streamView.setText(state.displayedText, streaming: false)
        }
    }

    // MARK: VoiceOver

    /// Announces a submit, a completion, a failure and a stop. Streaming text is never announced.
    private func announceTransition(from old: SessionState, to new: SessionState) {
        switch (old.phase, new.phase) {
        case (.running, .running):
            return
        case (_, .running):
            announce(PanelStrings.improvingFor(PanelMenus.displayName(of: session.target)))
        case (.running, .result):
            let words = new.shown?.text.split(whereSeparator: \.isWhitespace).count ?? 0
            announce(PanelStrings.done(words: words))
        case (.running, .failed):
            if let problem = problemPresentation(at: Date()) { announce(problem.line.text) }
        case (.running, .stopped):
            announce(PanelStrings.stoppedNotice)
        case (.running, .composing):
            announce(PanelStrings.stopped)
        default:
            return
        }
    }

    func announce(_ text: String) {
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    // MARK: What the views show

    /// The screen the panel shows right now.
    var screen: PanelScreen {
        PanelPresentation.screen(phase: session.state.phase, overlay: model.overlay, needsSetup: model.isSetupLatched)
    }

    /// The failure or stop the panel shows, if any. `now` drives a rate limit's countdown.
    func problemPresentation(at now: Date) -> PanelProblemPresentation? {
        let state = session.state
        switch state.phase {
        case .failed(let problem):
            var presentation = PanelProblemPresentation.make(
                for: problemWithProvider(problem),
                hasText: !state.liveText.isEmpty,
                elapsed: elapsed(of: state),
                retryRemaining: PanelProblemPresentation.retryRemaining(for: problem, endedAt: state.runEndedAt, now: now))
            if presentation.placement == .notice, presentation.recovery == .edit {
                presentation.recovery = .tryAgain
            }
            return presentation
        case .stopped:
            return .stopped
        case .composing, .running, .result:
            return nil
        }
    }

    /// A failure without a provider (a stream that just ended) names the one in use.
    private func problemWithProvider(_ problem: SessionProblem) -> SessionProblem {
        if case let .engine(error, nil, requestID) = problem {
            return .engine(error, provider: settings.provider, requestID: requestID)
        }
        return problem
    }

    private func elapsed(of state: SessionState) -> TimeInterval? {
        guard let start = state.runStartedAt, let end = state.runEndedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    /// A rate limit with a wait: the line and the recovery update every second.
    var problemHasCountdown: Bool {
        guard case .failed(.engine(.rateLimited(let retryAfter), _, _)) = session.state.phase else { return false }
        return retryAfter != nil
    }

    /// Whether the accent recovery is usable now (a rate limit's wait disables it).
    func isRecoveryEnabled(at now: Date) -> Bool {
        guard case .failed(let problem) = session.state.phase else { return true }
        return PanelProblemPresentation.retryRemaining(for: problem, endedAt: session.state.runEndedAt, now: now) == nil
    }

    /// What the footer shows at `now` (a rate limit's countdown changes it every second).
    func footerSpec(at now: Date) -> PanelFooterSpec {
        let state = session.state
        let screen = screen
        return PanelPresentation.footer(PanelFooterInput(
            screen: screen,
            draftStatus: session.draftValidation.status,
            hasRefineText: !model.refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            rewriteTargetName: state.needsRewriteForTarget ? PanelMenus.displayName(of: session.target) : nil,
            historyEnabled: historyAvailable,
            hasDisplayedText: !state.displayedText.isEmpty,
            recovery: problemPresentation(at: now)?.recovery ?? .tryAgain,
            isRecoveryEnabled: isRecoveryEnabled(at: now),
            isFullKeyboardAccessEnabled: model.isFullKeyboardAccessEnabled,
            targetCount: library.packs.count))
    }

    /// The result header's status at `now` (the elapsed seconds while thinking).
    func status(at now: Date) -> PanelStatus {
        let state = session.state
        return PanelPresentation.status(
            phase: state.phase,
            hasLiveText: !state.liveText.isEmpty,
            elapsed: state.runStartedAt.map { now.timeIntervalSince($0) },
            isCopied: state.isCopied)
    }

    /// The model that wrote what is on screen, for the status's tooltip.
    var writtenByModel: String? {
        let state = session.state
        let model = state.isRunning ? state.servedModel : (state.shown?.model ?? state.servedModel)
        guard let model, !model.isEmpty else { return nil }
        return ModelCatalog.curated.first { $0.model == model }?.displayName ?? model
    }

    var historyAvailable: Bool {
        settings.historyEnabled && dependencies.history != nil
    }

    // MARK: Keys

    /// The plain values `PanelKeyMap` decides with.
    func keyContext(now: Date = Date()) -> PanelKeyContext {
        let state = session.state
        let screen = screen
        var context = PanelKeyContext(screen: screen)
        context.isMenuOpen = model.openMenu != nil
        switch screen {
        case .compose: context.isPrimaryEnabled = session.canSubmit
        case .failed: context.isPrimaryEnabled = isRecoveryEnabled(at: now)
        case .setup: context.isPrimaryEnabled = model.setupStatus != .checking
        default: context.isPrimaryEnabled = true
        }
        context.canRecallOlder = state.draft.isEmpty || model.showsRecalledDraft
        context.canRecallNewer = model.showsRecalledDraft
        context.targetCount = library.packs.count
        context.isFullKeyboardAccessEnabled = NSApp.isFullKeyboardAccessEnabled
        context.historyEnabled = historyAvailable
        context.hasDisplayedText = !state.displayedText.isEmpty
        context.hasResultSelection = streamView.selectedText != nil
        context.hasFieldSelection = fieldHasSelection
        context.versionCount = state.versions.count
        context.shownVersion = state.shownVersion
        let visible = model.history.visible
        context.historyCount = visible.count
        context.hasHistorySelection = model.history.selectedIndex != nil
        context.canUndoDelete = model.history.deleted != nil
        return context
    }

    /// A text field (not the result text) has selected text, so ⌘C is the field's.
    private var fieldHasSelection: Bool {
        guard let textView = panel.firstResponder as? NSTextView, !textView.isDescendant(of: streamView) else { return false }
        return textView.selectedRange().length > 0
    }
}
