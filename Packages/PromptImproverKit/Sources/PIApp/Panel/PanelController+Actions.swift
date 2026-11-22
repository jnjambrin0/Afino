import AppKit
import PICore
import PIDesign
import PIPrompts
import PIProviders

/// What the keys, the buttons and the menus do.
extension PanelController {
    // MARK: Commands

    /// Runs a command from a key, a button or a menu row, then brings the panel up to date.
    func perform(_ command: PanelCommand) {
        switch command {
        case .primary: performPrimary()
        case .copyAndClose: copyAndClose()
        case .escape: escape()
        case .stop: session.stop()
        case .copy: copySelectionOrShown()
        case .regenerate: session.regenerate()
        case .retry: retry()
        case .editOriginal: session.editOriginal()
        case .toggleOriginal: toggleOriginal()
        case .newPrompt: session.newPrompt()
        case .insertNewline: input.textView.insertNewlineIgnoringFieldEditor(nil)
        case .nextTarget: session.cycleTarget(forward: true)
        case .previousTarget: session.cycleTarget(forward: false)
        case .selectTarget(let index): selectTarget(at: index)
        case .recallOlder: recall(older: true)
        case .recallNewer: recall(older: false)
        case .scrollUp: streamView.scrollLine(down: false)
        case .scrollDown: streamView.scrollLine(down: true)
        case .jumpToEnd: streamView.scrollToEnd()
        case .previousVersion: session.selectVersion(session.state.shownVersion - 1)
        case .nextVersion: session.selectVersion(session.state.shownVersion + 1)
        case .toggleActions: toggleMenu(.actions)
        case .toggleHistory: toggleHistory()
        case .openSettings: openSettings()
        case .menuPrevious: moveMenuHighlight(forward: false)
        case .menuNext: moveMenuHighlight(forward: true)
        case .menuExecute: executeHighlightedMenuItem()
        case .historyPrevious: moveHistorySelection(forward: false)
        case .historyNext: moveHistorySelection(forward: true)
        case .historyOpen: openSelectedHistoryEntry()
        case .historyDelete: deleteSelectedHistoryEntry()
        case .undoDelete: undoHistoryDelete()
        case .pasteKey: pasteKey()
        }
        refreshFromSession()
    }

    /// Return: what the accent button names.
    private func performPrimary() {
        switch screen {
        case .compose:
            guard session.canSubmit else { return }
            session.setDraft(input.draft)
            session.submit()
        case .result:
            let instruction = model.refineText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !instruction.isEmpty {
                refine(instruction)
            } else if session.state.needsRewriteForTarget {
                session.rewriteForTarget()
            } else {
                copyAndClose()
            }
        case .failed:
            guard isRecoveryEnabled(at: Date()) else { return }
            switch problemPresentation(at: Date())?.recovery ?? .tryAgain {
            case .tryAgain: retry()
            // Every problem that sends the user to Settings is about the key or the model.
            case .openSettings: openSettings(pane: .engine)
            case .edit: session.editOriginal()
            }
        case .stopped:
            retry()
        case .setup:
            saveKey()
        case .history:
            openSelectedHistoryEntry()
        case .running:
            return
        }
    }

    /// Sends `instruction` as a refinement of the shown version and clears the refine field.
    func refine(_ instruction: String) {
        refineField.setText("")
        model.refineText = ""
        session.refine(instruction)
    }

    private func retry() {
        guard isRecoveryEnabled(at: Date()) else { return }
        session.retry()
    }

    /// Esc backs out one level: a card, then the history, then a run (stopped, its text kept),
    /// then the panel. It never throws text away.
    private func escape() {
        if model.openMenu != nil {
            closeMenu(animated: true)
            return
        }
        switch screen {
        case .history:
            closeHistory()
        case .running:
            session.stop()
        default:
            dismiss(.escape)
        }
    }

    /// ⌘C: the selected result text, or everything shown.
    private func copySelectionOrShown() {
        if let selection = streamView.selectedText, !selection.isEmpty {
            dependencies.writeClipboard(selection)
        } else if !session.state.isRunning {
            session.copyShown()
        }
    }

    private func toggleOriginal() {
        guard session.state.origin != nil else { return }
        model.isOriginalExpanded.toggle()
    }

    private func selectTarget(at index: Int) {
        guard library.packs.indices.contains(index) else { return }
        session.setTarget(library.packs[index].id)
        if model.openMenu == .target { closeMenu(animated: true) }
    }

    private func recall(older: Bool) {
        session.recallDraft(older: older)
        model.showsRecalledDraft = !session.state.draft.isEmpty
        input.setDraft(session.state.draft)
    }

    /// Closes the panel and opens Settings, on `pane` when given.
    func openSettings(pane: SettingsPane? = nil) {
        closeMenu(animated: false)
        dismiss(.localInteraction)
        dependencies.openSettings(pane)
    }

    /// Shows the panel with the history list open (the menu bar's "History…").
    func presentHistory() {
        present()
        if model.overlay != .history { openHistory() }
    }

    /// The header measured its height (the original expanded or collapsed).
    func headerHeightDidChange(_ height: CGFloat) {
        let rounded = height.rounded()
        guard abs(rounded - model.headerHeight) > 0.5 else { return }
        model.headerHeight = max(rounded, EmberDesign.Panel.headerHeight)
        updateHeight(.header)
    }

    // MARK: Copy & Close

    /// Copies what is shown, gives the keyboard back to the previous app at once, then shrinks the
    /// panel into a "Copied" pill (a plain fade under Reduce Motion), holds it, and hides.
    func copyAndClose() {
        guard isPresented, !session.state.displayedText.isEmpty else { return }
        session.copyShown()
        closeMenu(animated: false)
        restorePreviousApplication()

        let reduceMotion = reduceMotion
        let startFrame = panel.frame
        model.isConfirmingCopy = true
        panel.ignoresMouseEvents = true
        let pill = CopiedPillView.pillSize()
        // Whole-point origin, exact size: the pill is a capsule of exactly `pillHeight`.
        let target = CGRect(
            x: (startFrame.midX - pill.width / 2).rounded(),
            y: (startFrame.midY - pill.height / 2).rounded(),
            width: pill.width,
            height: pill.height)
        surface.setCornerRadius(EmberDesign.Confirmation.pillRadius)
        let settle: TimeInterval
        if reduceMotion {
            PanelMotion.crossfade(panel, to: target, duration: EmberDesign.Motion.deliverReducedFadeDuration)
            settle = EmberDesign.Motion.deliverReducedFadeDuration * 2
        } else {
            shrinkAnimator.run(panel, to: target)
            settle = EmberDesign.Motion.deliverSettleDuration
        }
        let generation = visibilityGeneration
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settle + EmberDesign.Motion.deliverHoldDuration))
            guard let self, !Task.isCancelled, visibilityGeneration == generation else { return }
            dismiss(.copiedAndClosed)
        }
    }

    // MARK: Floating cards

    /// Opens a floating card, or closes it when it is the one already open. A card that has
    /// nothing to offer on the current screen does not open.
    func toggleMenu(_ kind: PanelMenuKind) {
        if model.openMenu == kind {
            closeMenu(animated: true)
            return
        }
        closeMenu(animated: false)
        switch kind {
        case .actions:
            guard PanelKeyMap.chord(for: .toggleActions, in: screen) != nil else { return }
            model.highlightedMenuItemID = nil
        case .target:
            guard screen != .running else { return }
            model.highlightedMenuItemID = "target.\(session.state.targetID)"
        }
        model.openMenu = kind
        showMenuWindow(kind)
    }

    func closeMenu(animated: Bool) {
        guard model.openMenu != nil else { return }
        model.openMenu = nil
        model.highlightedMenuItemID = nil
        cardWindow.hide(animated: animated && !reduceMotion)
    }

    private func showMenuWindow(_ kind: PanelMenuKind) {
        let placement = menuPlacement(kind)
        cardWindow.show(
            PanelMenuCardView(controller: self, kind: kind),
            anchor: placement.anchor,
            edge: placement.edge,
            preferAbove: true,
            parent: panel,
            reduceMotion: reduceMotion)
    }

    /// Keeps an open card next to its anchor while the panel changes height.
    func repositionMenu() {
        guard let kind = model.openMenu else { return }
        let placement = menuPlacement(kind)
        cardWindow.refit(anchor: placement.anchor, edge: placement.edge, preferAbove: true)
    }

    private func menuPlacement(_ kind: PanelMenuKind) -> (anchor: CGRect, edge: PanelCardPlacement.Edge) {
        switch kind {
        case .actions:
            let frame = model.actionsHintFrame
            let fallback = CGRect(x: panel.frame.width - EmberDesign.Panel.contentInset, y: panel.frame.height - EmberDesign.Panel.footerHeight, width: 0, height: EmberDesign.Panel.footerHeight)
            return (screenRect(fromContent: frame == .zero ? fallback : frame), .trailing)
        case .target:
            let frame = model.targetChipFrame
            let fallback = CGRect(x: PanelLayout.textLeadingInset, y: panel.frame.height - EmberDesign.Panel.footerHeight, width: 0, height: EmberDesign.Panel.footerHeight)
            return (screenRect(fromContent: frame == .zero ? fallback : frame), .leading)
        }
    }

    /// The rows of a card, built from the current session and settings each time it is drawn.
    func menuEntries(_ kind: PanelMenuKind) -> [PanelMenuEntry] {
        switch kind {
        case .actions:
            let state = session.state
            var context = PanelActionsMenuContext(screen: screen)
            context.hasOrigin = state.origin != nil
            context.isOriginalExpanded = model.isOriginalExpanded
            context.hasDisplayedText = !state.displayedText.isEmpty
            context.historyEnabled = historyAvailable
            context.customInstructionsEnabled = settings.customInstructionsEnabled
            context.usableProviders = ProviderID.allCases.filter { vault.state(for: $0).isUsable }
            context.provider = settings.provider
            context.preset = settings.preset
            if case .failed = state.phase { context.hasFailure = true }
            return PanelMenus.actions(context)
        case .target:
            return PanelMenus.targets(library: library, currentID: session.state.targetID, screen: screen)
        }
    }

    private func moveMenuHighlight(forward: Bool) {
        guard let kind = model.openMenu else { return }
        let ids = PanelMenus.selectableIDs(menuEntries(kind))
        guard !ids.isEmpty else { return }
        let current = model.highlightedMenuItemID.flatMap { ids.firstIndex(of: $0) }
        let next = HistoryRowFormatter.step(from: current, count: ids.count, forward: forward) ?? 0
        model.highlightedMenuItemID = ids[next]
    }

    private func executeHighlightedMenuItem() {
        guard let id = model.highlightedMenuItemID else { return }
        executeMenuItem(id)
    }

    /// Closes the open card and runs the row `id`, if it is enabled and does something.
    func executeMenuItem(_ id: String) {
        guard let kind = model.openMenu,
              let entry = menuEntries(kind).first(where: { $0.id == id }),
              entry.item.isEnabled,
              let action = entry.action else { return }
        closeMenu(animated: true)
        switch action {
        case .command(let command):
            perform(command)
        case .refinePreset(let phrase):
            refine(phrase)
        case .engine(let provider, let preset):
            settings.provider = provider
            settings.preset = preset
        case .customInstructions:
            openSettings(pane: .instructions)
        case .copyDetails:
            copyDetails()
        case .target(let targetID):
            session.setTarget(targetID)
        }
        refreshFromSession()
    }

    /// Provider, model, request id and the error's case; never the draft or a provider message.
    private func copyDetails() {
        guard case .failed(let problem) = session.state.phase else { return }
        var provider = settings.provider
        var requestID: String?
        if case let .engine(_, failedProvider, failedRequest) = problem {
            provider = failedProvider ?? provider
            requestID = failedRequest
        }
        let model = session.state.servedModel ?? settings.engineSelection.model
        let lines = [
            PanelStrings.detailsProvider(provider.displayName),
            PanelStrings.detailsModel(model),
            PanelStrings.detailsRequest(requestID ?? PanelStrings.detailsNone),
            PanelStrings.detailsError(PanelProblemPresentation.caseDescription(of: problem)),
        ]
        dependencies.writeClipboard(lines.joined(separator: "\n"))
    }

    // MARK: Add-a-key card

    /// The provider chips: switching is refused while a key is being checked.
    func selectProvider(_ provider: ProviderID) {
        guard model.setupStatus != .checking, settings.provider != provider else { return }
        settings.provider = provider
        model.setupStatus = .idle
        keyField.setPlaceholder(PanelStrings.keyPlaceholder(provider.displayName))
        refreshFromSession()
    }

    /// Paste reads the clipboard only when asked (the button or ⌘V), then checks the key at once.
    func pasteKey() {
        guard model.setupStatus != .checking,
              let text = dependencies.readClipboard()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        keyField.setText(text)
        model.setupKeyText = text
        saveKey()
    }

    /// Saves the typed key to the vault, which checks it with the provider, and shows the outcome.
    func saveKey() {
        guard model.setupStatus != .checking else { return }
        let key = model.setupKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            model.setupStatus = .empty
            return
        }
        let provider = settings.provider
        model.setupStatus = .checking
        setupTask?.cancel()
        setupTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await vault.save(key, for: provider)
            guard !Task.isCancelled else { return }
            await keyCheckFinished(outcome)
        }
    }

    private func keyCheckFinished(_ outcome: KeyCheckOutcome) async {
        switch outcome {
        case .valid:
            model.setupStatus = .accepted
            announce(PanelStrings.keyWorks)
            try? await Task.sleep(for: PanelLayout.keyAcceptedHold)
            completeSetup()
        case .savedUnverified, .savedWithLimitedAccess:
            model.setupStatus = .unverified
            announce(PanelStrings.keyUnverified)
            try? await Task.sleep(for: PanelLayout.keyUnverifiedHold)
            completeSetup()
        case .rejected:
            model.setupStatus = .rejected
            announce(PanelStrings.keyRejected)
        case .wrongProvider(let other):
            model.setupStatus = .wrongProvider(other)
            announce(PanelStrings.wrongProvider(other.displayName))
        case .empty:
            model.setupStatus = .empty
        case .storeFailed:
            model.setupStatus = .storeFailed
            announce(PanelStrings.keyStoreFailed)
        }
        refreshFromSession()
    }

    /// The key works: straight to the composer.
    private func completeSetup() {
        keyField.setText("")
        model.setupKeyText = ""
        model.setupStatus = .idle
        refreshFromSession()
    }

    /// "This looks like an OpenAI key." → "Use OpenAI": switches provider and saves again.
    func useProvider(_ provider: ProviderID) {
        settings.provider = provider
        model.setupStatus = .idle
        keyField.setPlaceholder(PanelStrings.keyPlaceholder(provider.displayName))
        saveKey()
    }

    /// "Get a key": the chosen provider's API key page in the browser.
    func openKeyPage() {
        dependencies.openURL(Self.keyPage(for: settings.provider))
    }

    private static func keyPage(for provider: ProviderID) -> URL {
        switch provider {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    // MARK: History

    /// ⌘Y: opens the history list, or leaves it.
    func toggleHistory() {
        if model.overlay == .history {
            closeHistory()
        } else {
            openHistory()
        }
    }

    private func openHistory() {
        guard historyAvailable, let store = dependencies.history, !session.state.isRunning else { return }
        closeMenu(animated: false)
        filterField.setText("")
        model.history.filter = ""
        model.history.deleted = nil
        model.overlay = .history
        refreshFromSession()
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            let entries = await store.all()
            guard let self, !Task.isCancelled, model.overlay == .history else { return }
            model.history.entries = entries
            model.history.isLoaded = true
            model.history.selectedID = model.history.visible.first?.id
            updateHeight(.screen)
        }
    }

    func closeHistory() {
        guard model.overlay == .history else { return }
        historyTask?.cancel()
        model.overlay = .none
        model.history.deleted = nil
        toastTask?.cancel()
        refreshFromSession()
    }

    func historyFilterDidChange(_ text: String) {
        model.history.filter = text
        model.history.selectedID = model.history.visible.first?.id
        updateHeight(.list)
    }

    private func moveHistorySelection(forward: Bool) {
        let visible = model.history.visible
        guard let next = HistoryRowFormatter.step(from: model.history.selectedIndex, count: visible.count, forward: forward) else { return }
        model.history.selectedID = visible[next].id
    }

    private func openSelectedHistoryEntry() {
        guard let index = model.history.selectedIndex else { return }
        openHistoryEntry(model.history.visible[index])
    }

    /// Opens a past improvement as a result, ready to refine (and copies it, as any result is).
    func openHistoryEntry(_ entry: HistoryEntry) {
        session.open(entry)
        closeHistory()
    }

    private func deleteSelectedHistoryEntry() {
        guard let store = dependencies.history, let index = model.history.selectedIndex else { return }
        let visible = model.history.visible
        let entry = visible[index]
        // The selection moves to the neighbour, as in a list.
        let neighbour = visible.indices.contains(index + 1) ? visible[index + 1] : (index > 0 ? visible[index - 1] : nil)
        model.history.entries.removeAll { $0.id == entry.id }
        model.history.selectedID = neighbour?.id
        model.history.deleted = entry
        updateHeight(.list)
        Task { [weak self] in
            _ = try? await store.remove(id: entry.id)
            await self?.session.refreshRecallDrafts()
        }
        showUndoToast()
    }

    private func showUndoToast() {
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(EmberDesign.Motion.toastLifetime))
            guard let self, !Task.isCancelled else { return }
            model.history.deleted = nil
        }
    }

    /// ⌘Z or the toast's Undo: puts the deleted entry back and selects it.
    func undoHistoryDelete() {
        guard let entry = model.history.deleted, let store = dependencies.history else { return }
        toastTask?.cancel()
        model.history.deleted = nil
        Task { [weak self] in
            try? await store.restore(entry)
            let entries = await store.all()
            await self?.session.refreshRecallDrafts()
            guard let self, model.overlay == .history else { return }
            model.history.entries = entries
            model.history.selectedID = entry.id
            updateHeight(.list)
        }
    }
}
