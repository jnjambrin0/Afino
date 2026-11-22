import Foundation
import Observation
import os
import PIFoundation
import PIPrompts
import PIProviders

/// One prompt being improved: the draft, the runs, the versions.
///
/// The panel reads `state` and calls the methods below; it never changes state itself. A run keeps
/// going when the panel is hidden, and its result is copied when it completes.
@Observable
public final class ImproveSession {
    /// Everything the panel shows. Observed by the panel, the menu bar item and VoiceOver
    /// announcements; changed only through `RunReducer`.
    public private(set) var state: SessionState

    @ObservationIgnored private let settings: SettingsModel
    @ObservationIgnored private let vault: CredentialVault
    /// The targets the session can write for.
    @ObservationIgnored public let library: TargetPackLibrary
    @ObservationIgnored private let composer: PromptComposer
    @ObservationIgnored private let providers: [ProviderID: any PromptEngineProvider]
    @ObservationIgnored private let clipboard: any ClipboardWriting
    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let now: () -> Date

    /// Bumped by every start and stop. A run's task drops whatever arrives once its number is no
    /// longer current, so a stopped or replaced run never reaches the reducer.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The conversation of the run in flight, and how it was started (for Try Again).
    @ObservationIgnored private var inFlight: (conversation: PromptConversation, kind: RunKind)?
    /// For each version, the conversation that produced it: what Regenerate sends again and what
    /// Refine extends.
    @ObservationIgnored private var producedBy: [PromptConversation] = []
    /// One history entry per session; refinements update it.
    @ObservationIgnored private var historyEntryID = UUID()
    /// Past drafts for ↑ in an empty input, newest first, and where the user is in them.
    @ObservationIgnored private var recallDrafts: [String] = []
    @ObservationIgnored private var recallIndex: Int?

    public init(
        settings: SettingsModel,
        vault: CredentialVault,
        library: TargetPackLibrary,
        composer: PromptComposer,
        providers: [ProviderID: any PromptEngineProvider],
        clipboard: any ClipboardWriting,
        history: HistoryStore?,
        now: @escaping () -> Date = { Date() }
    ) {
        self.settings = settings
        self.vault = vault
        self.library = library
        self.composer = composer
        self.providers = providers
        self.clipboard = clipboard
        self.history = history
        self.now = now
        state = SessionState(targetID: library.pack(for: settings.initialTargetID).id)
    }

    // MARK: - What the panel reads

    /// The chosen target's pack.
    public var target: TargetPack { library.pack(for: state.targetID) }

    /// The draft checked against `DraftLimits`.
    public var draftValidation: DraftValidation { DraftLimits.validate(state.draft) }

    /// Whether Return in the composer would start a run.
    public var canSubmit: Bool { state.phase == .composing && draftValidation.isSubmittable }

    /// Whether the chosen provider has a key to send. When it does not, the panel shows the
    /// add-a-key card instead of the composer.
    public var hasUsableKey: Bool { vault.state(for: settings.provider).isUsable }

    // MARK: - Editing

    /// The compose input changed.
    public func setDraft(_ draft: String) {
        guard draft != state.draft else { return }
        recallIndex = nil
        dispatch(.setDraft(draft))
    }

    /// Picks a target (not while a run is in flight) and remembers it as the last one used.
    public func setTarget(_ id: String) {
        let pack = library.pack(for: id)
        guard pack.id != state.targetID, !state.isRunning else { return }
        settings.lastTargetID = pack.id
        dispatch(.setTarget(pack.id))
    }

    /// Tab and Shift-Tab in the composer: the next or previous target, wrapping round.
    public func cycleTarget(forward: Bool) {
        let packs = library.packs
        guard let index = packs.firstIndex(where: { $0.id == state.targetID }), packs.count > 1 else { return }
        let next = (index + (forward ? 1 : packs.count - 1)) % packs.count
        setTarget(packs[next].id)
    }

    /// ↑ and ↓ in an empty or recalled input: steps through earlier drafts. Returns whether the
    /// key was used.
    @discardableResult
    public func recallDraft(older: Bool) -> Bool {
        guard state.phase == .composing, !recallDrafts.isEmpty else { return false }
        if let index = recallIndex {
            guard state.draft == recallDrafts[index] else { return false }
            let next = older ? index + 1 : index - 1
            if next < 0 {
                recallIndex = nil
                dispatch(.setDraft(""))
                return true
            }
            guard recallDrafts.indices.contains(next) else { return true }
            recallIndex = next
            dispatch(.setDraft(recallDrafts[next]))
            return true
        }
        guard older, state.draft.isEmpty else { return false }
        recallIndex = 0
        dispatch(.setDraft(recallDrafts[0]))
        return true
    }

    // MARK: - Runs

    /// Return in the composer.
    public func submit() {
        guard canSubmit else { return }
        let draft = state.draft
        historyEntryID = UUID()
        producedBy = []
        start(composer.startConversation(draft: draft, target: target), kind: .first, draft: draft)
    }

    /// Return in the refine field.
    public func refine(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.phase == .result, !trimmed.isEmpty, let shown = state.shown, let origin = state.origin,
              producedBy.indices.contains(state.shownVersion) else { return }
        let conversation = producedBy[state.shownVersion]
            .appendingRevision(previousOutput: shown.text, instruction: trimmed)
        start(conversation, kind: .refine(instruction: trimmed), draft: origin)
    }

    /// ⌘R on a result: the same request again, as a new version.
    public func regenerate() {
        guard state.phase == .result, let origin = state.origin,
              producedBy.indices.contains(state.shownVersion) else { return }
        start(producedBy[state.shownVersion], kind: .regenerate, draft: origin)
    }

    /// Return on a result after the target was changed: the original draft, for the new target.
    public func rewriteForTarget() {
        guard state.needsRewriteForTarget, let origin = state.origin else { return }
        start(composer.startConversation(draft: origin, target: target), kind: .rewriteForTarget, draft: origin)
    }

    /// Try Again after a failure or a stop: the request that did not finish, unchanged.
    public func retry() {
        switch state.phase {
        case .failed, .stopped:
            guard let inFlight, let origin = state.origin else { return }
            start(inFlight.conversation, kind: inFlight.kind, draft: origin)
        case .composing, .running, .result:
            return
        }
    }

    /// Stops the run in flight; what it had written stays on screen.
    public func stop() {
        guard state.isRunning else { return }
        generation &+= 1
        task?.cancel()
        task = nil
        dispatch(.stop(at: now()))
    }

    /// Back to the composer with the draft the versions were written from.
    public func editOriginal() { dispatch(.editOriginal) }

    /// Back to an empty composer.
    public func newPrompt() { dispatch(.newPrompt) }

    /// Shows the version at `index` and copies it.
    public func selectVersion(_ index: Int) { dispatch(.selectVersion(index)) }

    /// ⌘C with nothing selected: the whole text on screen.
    public func copyShown() { dispatch(.copyShown) }

    /// The panel was dismissed. A run in flight carries on; a finished session ends.
    public func panelDidClose() { dispatch(.panelClosed) }

    /// Opens a past improvement as a result, ready to refine.
    public func open(_ entry: HistoryEntry) {
        guard !state.isRunning, !entry.versions.isEmpty else { return }
        let entryPack = library.pack(for: entry.targetID)
        var conversation = composer.startConversation(draft: entry.draft, target: entryPack)
        var conversationTargetID = entryPack.id
        var conversations: [PromptConversation] = []
        var versions: [PromptVersion] = []
        for (index, version) in entry.versions.enumerated() {
            let pack = library.pack(for: version.targetID ?? entry.targetID)
            if pack.id != conversationTargetID {
                // Rewritten for another target: that version started a conversation of its own.
                conversation = composer.startConversation(draft: entry.draft, target: pack)
                conversationTargetID = pack.id
            } else if index > 0, let instruction = version.instruction {
                conversation.appendRevision(previousOutput: entry.versions[index - 1].text, instruction: instruction)
            }
            conversations.append(conversation)
            versions.append(PromptVersion(text: version.text, instruction: version.instruction, targetID: pack.id, model: entry.model))
        }
        let shownTargetID = versions.last?.targetID ?? entryPack.id
        historyEntryID = entry.id
        producedBy = conversations
        inFlight = nil
        dispatch(.restore(draft: entry.draft, targetID: shownTargetID, versions: versions))
    }

    /// Loads the drafts ↑ steps through. Call at launch and it refreshes itself after each run.
    public func refreshRecallDrafts() async {
        guard settings.historyEnabled, let history else {
            recallDrafts = []
            return
        }
        recallDrafts = await history.recentDrafts()
    }

    // MARK: - Sending a run

    private func start(_ conversation: PromptConversation, kind: RunKind, draft: String) {
        generation &+= 1
        let runID = generation
        task?.cancel()
        inFlight = (conversation, kind)
        recallIndex = nil
        dispatch(.began(runID: runID, kind: kind, draft: draft, at: now()))

        let selection = settings.engineSelection
        guard let provider = providers[selection.provider], let key = vault.key(for: selection.provider) else {
            dispatch(.failed(
                runID: runID,
                EngineFailure(.missingKey(selection.provider), provider: selection.provider),
                at: now()))
            return
        }

        let prompt = composer.compose(conversation, target: target, preferences: settings.promptPreferences)
        let inputCharacters = prompt.turns.reduce(0) { $0 + $1.text.count }
        let request = EngineRequest(
            selection: selection,
            maxOutputTokens: ModelCatalog.maxOutputTokens(forInputCharacters: inputCharacters, capabilities: selection.capabilities),
            systemBlocks: prompt.systemBlocks,
            turns: prompt.turns.map { turn in
                switch turn {
                case .user(let text): .user(text)
                case .assistant(let text): .assistant(text)
                }
            })
        Log.logger(.engine).info(
            "Run \(runID, privacy: .public) → \(selection.model, privacy: .public), \(inputCharacters, privacy: .public) input characters")

        let stream = provider.stream(request, key: key)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, self.generation == runID else { return }
                    self.dispatch(.event(runID: runID, event, at: self.now()))
                }
                guard let self, self.generation == runID else { return }
                self.dispatch(.streamEnded(runID: runID, at: self.now()))
            } catch {
                guard let self, self.generation == runID else { return }
                self.dispatch(.failed(
                    runID: runID,
                    EngineFailure(normalizing: error, provider: selection.provider),
                    at: self.now()))
            }
        }
    }

    private func dispatch(_ action: SessionAction) {
        let versionsBefore = state.versions.count
        let effects = RunReducer.reduce(&state, action)
        if state.versions.count == versionsBefore + 1, let inFlight {
            producedBy.append(inFlight.conversation)
        }
        if case .newPrompt = action { producedBy = [] }
        if case .editOriginal = action { producedBy = [] }
        for effect in effects {
            perform(effect)
        }
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .copy(let text):
            clipboard.write(text)
        case .recordHistory:
            recordHistory()
        case .keyRejected(let provider):
            vault.markRejected(provider)
        }
    }

    private func recordHistory() {
        guard settings.historyEnabled, let history, let origin = state.origin, !state.versions.isEmpty else { return }
        let selection = settings.engineSelection
        let entry = HistoryEntry(
            id: historyEntryID,
            date: now(),
            draft: origin,
            targetID: state.versions[0].targetID,
            versions: state.versions.map { version in
                .init(
                    text: version.text,
                    instruction: version.instruction,
                    targetID: version.targetID == state.versions[0].targetID ? nil : version.targetID)
            },
            provider: selection.provider.rawValue,
            model: state.shown?.model.isEmpty == false ? state.shown?.model ?? selection.model : selection.model)
        Task { [weak self] in
            do {
                try await history.record(entry)
            } catch {
                Log.logger(.store).error("Could not save the history")
            }
            await self?.refreshRecallDrafts()
        }
    }
}
