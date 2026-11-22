# Architecture

Afino is a macOS 26 menu bar agent whose Xcode app target is a one-line shell over a Swift package, `PromptImproverKit`, split into layered modules. This page maps the repository, follows one improvement from the global shortcut to the clipboard, and says where state, secrets and files live.

The repository, the Xcode project, the package, the `PI` module prefix, the bundle identifier `com.jnjambrin0.PromptImprover` and the update feed keep the pre-1.0 name on purpose: the bundle identifier carries existing preferences and Keychain items, and installed copies poll the feed URL.

## Repository map

| Path | What it holds |
|---|---|
| [`PromptImprover/`](../PromptImprover/main.swift) | The app target: `main.swift` (one call to `PromptImproverApplication.main()`), the app icon, the menu bar glyph, `InfoPlist.xcstrings`. |
| [`PromptImprover.xcodeproj/`](../PromptImprover.xcodeproj/project.xcproj) | The project in Xcode's JSON format: one target that builds `Afino.app` and links the package product `PIApp`. |
| [`Packages/PromptImproverKit/`](../Packages/PromptImproverKit/Package.swift) | All the code: seven source targets, their tests, the bundled prompt resources. |
| [`Config/`](../Config/Info.plist) | `Info.plist` for both configurations; `Release.xcconfig`, which sets the update feed URL. |
| [`scripts/`](../scripts/test.sh) | `test.sh`, `build.sh`, `run.sh`, and the release pipeline in `release/`. |
| `docs/` | This file, [EVALUATION.md](EVALUATION.md), [RELEASING.md](RELEASING.md), [BRAND.md](BRAND.md), and the README images in `images/`. |
| [`design/`](../design/generate-icons.swift) | Brand generators and image composition scripts: `generate-icons.swift` (app icon, menu bar glyph), `render-dmg-background.swift`, and `capture-screenshots.sh` plus `render-doc-images.swift` for `docs/images/`. |
| `.github/` | Issue and pull request templates, the funding file. |

`build/` is git-ignored; `scripts/build.sh` puts DerivedData there and `prompt-eval` writes reports to `build/eval/`. Debug builds are `com.jnjambrin0.PromptImprover.dev` with development signing; Release builds are `com.jnjambrin0.PromptImprover`, signed with Developer ID, hardened runtime, no App Sandbox.

## Module layers and why

[`Package.swift`](../Packages/PromptImproverKit/Package.swift) declares this graph. Each module depends only on layers below it; modules on one layer never import each other.

```
L3  PIApp           composition root; the only module that links Sparkle
L2  PICore          → PIProviders, PIPrompts, PIFoundation
L1  PIProviders     → PIFoundation
    PIPrompts       → PIFoundation
    PIDesign        (no dependencies inside the package)
L0  PIFoundation

    PromptEval      executable `prompt-eval` → PIPrompts, PIProviders, PIFoundation
                    beside the layers, never linked into the app
```

| Module | Owns |
|---|---|
| PIFoundation | `ConfigStore` (typed `UserDefaults`), `SecretStore` and `KeychainSecretStore`, `Log`, `AppIdentity`, atomic JSON writes, owner-only file permissions. |
| PIProviders | `PromptEngineProvider`, the Anthropic and OpenAI clients, SSE transport, retries, `EngineError`, `APIKey`, `ModelCatalog`. |
| PIPrompts | The engine prompt and target packs, `PromptComposer`, `PromptConversation`, `DraftLimits`, `OutputPostProcessor`. |
| PIDesign | `EmberDesign` tokens, the `E…` components, key-chord formatting. |
| PICore | `ImproveSession` and `RunReducer`, `SettingsModel`, `CredentialVault`, `HistoryStore`, `ModelCatalogStore`, `LegacyCleanup`, the clipboard seam. |
| PIApp | `AppDelegate` and `AppServices`, the panel, Settings, the welcome, the menu bar item, hot keys, `UpdateController`. |
| PromptEval | The evaluation tool. Its own tests run offline in `swift test`. |

**Isolation.** All targets use Swift 6. The UI modules (PIDesign, PICore, PIApp and their tests) add `.defaultIsolation(MainActor.self)`; PIFoundation, PIProviders, PIPrompts and PromptEval are nonisolated by default.

**Why.** The logic below the interface is testable without windows, network or Keychain: `SessionState` is a value changed only by `RunReducer`; providers take an injected `URLSession`, clock and jitter source; PIPrompts reads only bundled text. `AppDelegate` builds every service once and passes it down by initializer, so tests can swap any of them. Sparkle stays behind `UpdateController`, and `prompt-eval` can run the shipped engine from a terminal because it imports no UI. [`ArchitectureLintTests`](../Packages/PromptImproverKit/Tests/PIAppTests/ArchitectureLintTests.swift) enforce the import graph, keep AppKit and SwiftUI out of the headless modules, and forbid `static let shared` singletons, `URLSession.shared`, `print`, `ObservableObject`, Keychain calls outside `KeychainSecretStore`, and `UserDefaults.standard` outside `ConfigStore` (except in `LegacyCleanup` and the updater).

## The life of one improvement

1. **Launch.** `PromptImproverApplication.main()` sets the `.accessory` activation policy and installs [`AppDelegate`](../Packages/PromptImproverKit/Sources/PIApp/AppDelegate.swift). `launch()` checks for another running copy, offers (Release only) to move the app to Applications, builds [`AppServices`](../Packages/PromptImproverKit/Sources/PIApp/AppServices.swift), loads stored keys, installs the menus, registers the shortcut, creates `PanelController`, shows the welcome on first launch and starts the updater. An unreadable bundled pack or `core.txt` makes `AppServices.init` throw, and the app quits. The panel's window and view tree are built once and painted invisibly once (`PanelController.prewarm()`).

2. **Shortcut.** [`ActivationShortcut`](../Packages/PromptImproverKit/Sources/PIApp/Input/ActivationShortcut.swift) chooses ⌃⌥P on first launch, or ⌃⌥⌘P when ⌃⌥P is taken, and stores the choice (a stored `null` means the user turned it off). [`HotKeyCenter`](../Packages/PromptImproverKit/Sources/PIApp/Input/HotKeyCenter.swift) registers it with Carbon's `RegisterEventHotKey`, which needs no Accessibility permission, and runs the action on the main run loop: `PanelController.toggle(pressedAt:)`.

3. **Panel.** [`PanelController.present()`](../Packages/PromptImproverKit/Sources/PIApp/Panel/PanelController.swift) picks the display under the pointer, records the frontmost app in `FocusHandoff`, focuses the field the screen calls for, activates through `AppActivator` (cooperative `NSApp.activate()`, then `activate(ignoringOtherApps:)` if not honoured within 50 ms), orders the panel in and installs event monitors (the global one sees only clicks, to close on a click elsewhere). `PromptPanel` is a borderless, activating, always-dark `NSPanel` whose content sits in an `NSGlassEffectView` (`PanelGlassSurfaceView`).

4. **Draft and target.** Every key-down goes first to [`PanelKeyMap`](../Packages/PromptImproverKit/Sources/PIApp/PanelUI/PanelKeyMap.swift); unclaimed keys reach the focused view. Typing calls `ImproveSession.setDraft`; Tab and ⇧Tab call `cycleTarget(forward:)` (not under Full Keyboard Access, where Tab moves focus); ⌘1…⌘9 pick a target. `DraftLimits` blocks a blank draft, warns above 8,000 characters and refuses more than 30,000, never truncating. Without a usable key for the chosen provider, an add-a-key card replaces the composer.

5. **Submit.** Return calls [`ImproveSession.submit()`](../Packages/PromptImproverKit/Sources/PICore/Session/ImproveSession.swift), which starts a `PromptConversation` and calls `start(_:kind:draft:)`: bump the run generation, dispatch `.began(runID:…)`, resolve `SettingsModel.engineSelection`, take the key from `CredentialVault`, build an `EngineRequest` from `PromptComposer.compose` with an output budget from `ModelCatalog.maxOutputTokens(forInputCharacters:capabilities:)`, and iterate `provider.stream(request, key:)` in a `Task`.

6. **Streaming.** `StreamDriver` runs `SSEClient` once per attempt under `RetryPolicy`; `SSEParser` splits the bytes into events and the provider's `SSEStreamHandler` turns them into `EngineEvent`s: `.retrying`, `.started`, `.thinking`, `.textDelta`, `.finished`. Failures arrive as `EngineFailure`.

7. **Reducer and effects.** Each event goes through [`RunReducer.reduce`](../Packages/PromptImproverKit/Sources/PICore/Session/RunReducer.swift), which updates `SessionState` and returns `SessionEffect`s without touching anything else. `.finished(.complete)` finalises the text, appends a `PromptVersion`, enters `.result` and returns `.copy`, `.recordHistory` and `.completed`. `ImproveSession` performs them: `SystemClipboard` writes plain text with no transient marker, so clipboard managers keep it, and `HistoryStore` records the session.

8. **What the panel shows.** `PanelController+Session` observes `session.state` with `withObservationTracking`; `refreshFromSession()` derives the screen, the text in `StreamTextView` (a paced reveal through `StreamRevealBuffer`), the height, the footer, VoiceOver announcements, and failures as one line plus a recovery (`PanelProblemPresentation`).

9. **Copy & Close.** On a result, Return with an empty refine field, or ⌘Return, runs `copyAndClose()`: copy the shown text, hand the keyboard back with `FocusHandoff.restorePreviousApplicationIfPossible()` (`NSApp.yieldActivation(to:)`, then `activate(from:)`, retried briefly), shrink into a "Copied" pill and hide. Afino never types into the other app. Esc, the shortcut and ⌘W also restore the previous app; a click elsewhere or an app switch does not.

## The session state machine

[`SessionState.phase`](../Packages/PromptImproverKit/Sources/PICore/Session/SessionState.swift) is `.composing`, `.running(RunStage)` (connecting, thinking, writing, retrying), `.result`, `.failed(SessionProblem)` or `.stopped`.

| From | Action | To |
|---|---|---|
| composing | `submit()` | running |
| running | `.finished(.complete)` with text | result (copied, recorded) |
| running | error, truncation, refusal, empty output, stream ended early | failed (partial text kept, not copied) |
| running | `stop()` before any text | composing with the draft, or result if earlier versions exist |
| running | `stop()` after some text | stopped (partial text kept) |
| result | `refine`, `regenerate`, `rewriteForTarget` | running |
| failed, stopped | `retry()` | running |
| result, failed, stopped | `editOriginal()`, `newPrompt()` | composing |

**Superseded runs.** `ImproveSession` bumps a `generation` counter on every start and stop; the stream's task dispatches only while `generation == runID`, and `stop()` cancels it, which cancels the request and any back-off wait. Independently, every run action carries its `runID` and the reducer drops it unless it matches `state.runID`; `.stop` increments `state.runID` itself. Stop followed at once by Improve is therefore safe from the old run's tail.

**Hiding mid-run.** One `ImproveSession` lives for the whole app, owned by `AppServices`, not the panel. On hide, `.panelClosed` leaves a running run alone, so it still copies and records its result; a finished result resets to an empty draft, and a failed or stopped one returns to composing with its draft. The menu bar icon shows a checkmark when a run completes while hidden and a dot when one fails.

**Versions.** Each completed run appends a `PromptVersion`; ⌘[ and ⌘] select and copy one. `ImproveSession` keeps the `PromptConversation` behind each version. Refine extends it with the shown text and a `<revision_request>` turn (the last 12 revisions are kept); Regenerate (⌘R) resends it; Try Again resends the unfinished request unchanged. Choosing another target on a result sets `needsRewriteForTarget`, and Return starts a fresh conversation from the original draft, since the first message names the target. A session's versions share one `HistoryEntry`.

## Where things live

Preferences, the data folder, the Keychain service and the log subsystem all follow the running app's bundle identifier (`AppIdentity`), so a Debug build keeps them apart from an installed release.

| What | Where and how |
|---|---|
| API keys | [`KeychainSecretStore`](../Packages/PromptImproverKit/Sources/PIFoundation/Secrets/KeychainSecretStore.swift): login-keychain generic passwords, service `<bundle id>.apikeys`, account `anthropic` or `openai`, `kSecAttrSynchronizable` false, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Preferences hold only a per-provider "verified" flag; `APIKey` prints masked. |
| Keys in Debug | `AppServices.makeSecretStore()` uses `EnvironmentSecretStore` when `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` is set, or `InMemorySecretStore` with `--in-memory-secrets`. Release builds always use the Keychain. |
| Settings | [`ConfigStore`](../Packages/PromptImproverKit/Sources/PIFoundation/Config/ConfigStore.swift) over `UserDefaults.standard`, mostly through `SettingsModel`. Only changed values are stored, so defaults can change without a migration. |
| History | [`HistoryStore`](../Packages/PromptImproverKit/Sources/PICore/History/HistoryStore.swift): `~/Library/Application Support/<bundle id>/history.json`, at most 50 entries, folder `0700`, file `0600`, atomic writes. A corrupt file is set aside; a newer schema is left untouched. The `historyEnabled` setting stops recording; Settings › General can clear it. |
| Model lists | Memory only, in `ModelCatalogStore`. |
| Logs | [`Log`](../Packages/PromptImproverKit/Sources/PIFoundation/Log.swift): unified logging by category. Sizes, counts, status codes, request ids, model ids and timings; never drafts, results, request bodies or keys. Provider messages pass through `Redactor`. |
| 0.x leftovers | [`LegacyCleanup`](../Packages/PromptImproverKit/Sources/PICore/Legacy/LegacyCleanup.swift) runs off the main thread until it succeeds once: it deletes old caches, temporary files and preference keys, then moves `~/Library/Application Support/PromptImprover` to `…/<bundle id>/Legacy-0.x` if it holds user guides, or to the Trash. |

## Target packs and the engine prompt

The engine's text ships in [`PIPrompts/Resources`](../Packages/PromptImproverKit/Sources/PIPrompts/Resources/core.txt): `core.txt` is the system prompt, and each target is a folder `Packs/<id>/` holding exactly `pack.json` (id, names, `promptLabel`, covered models, badge, sort order, sources, review date) and `guidance.md`. [`TargetPackLibrary`](../Packages/PromptImproverKit/Sources/PIPrompts/TargetPackLibrary.swift) validates every pack strictly and throws on anything malformed, a packaging bug. Library and `core.txt` are read once at launch and kept in memory.

[`PromptComposer`](../Packages/PromptImproverKit/Sources/PIPrompts/PromptComposer.swift) assembles the request, stable part first so providers can cache it as a prefix: CORE (`core.txt` verbatim), PACK (`<target_guidance>`), then PREFS (`<user_preferences>`, only when the output language is English or custom instructions are on, capped at 2,000 characters). Nothing dynamic enters these blocks. The turns follow: the draft inside `<draft id="…">` with a random id absent from the draft, so pasted text cannot close the tag, then any refinements.

[`OutputPostProcessor`](../Packages/PromptImproverKit/Sources/PIPrompts/OutputPostProcessor.swift) only trims, unwraps one outer code fence and strips one "Here is the prompt:" preface line; it never rejects or truncates. Changes to `core.txt`, a pack or the composer should come with an evaluation run ([EVALUATION.md](EVALUATION.md)).

## Providers

| | `AnthropicProvider` | `OpenAIProvider` |
|---|---|---|
| Stream | `POST /v1/messages` | `POST /v1/responses` |
| Key check | `GET /v1/models` | `GET /v1/models` |
| System text | `system` blocks, `cache_control` on the last | one `developer` item |
| Effort | `output_config.effort`, optional `thinking: disabled` | `reasoning.effort` |
| Other | server-side fallback for models that support it | `store: false` |

Both share one ephemeral `URLSession` ([`ProviderSession`](../Packages/PromptImproverKit/Sources/PIProviders/Transport/ProviderSession.swift)) with no cache, cookies or credential storage; auth headers are set per request. [`SSEClient`](../Packages/PromptImproverKit/Sources/PIProviders/Transport/SSEClient.swift) reads the byte stream and runs two watchdogs: 20 s for the response head, 300 s of silence once the answer started. [`RetryPolicy.standard`](../Packages/PromptImproverKit/Sources/PIProviders/Transport/RetryPolicy.swift) allows 3 attempts, only before any text arrived and only for retryable failures (408, 409, non-billing 429, 500, 502–504, 529, dropped connections, a missing response head); it honours `Retry-After` up to 20 s (a longer wait fails at once) and otherwise waits 0.5 s, then 1.5 s, with jitter.

Every failure is an `EngineFailure`: an [`EngineError`](../Packages/PromptImproverKit/Sources/PIProviders/Model/EngineError.swift) plus provider, request id and HTTP status. Provider text survives only in `invalidRequest`, after redaction. [`ModelCatalog`](../Packages/PromptImproverKit/Sources/PIProviders/Catalog/ModelCatalog.swift) holds the curated models with their capabilities and the Fast, Balanced and Quality presets per provider; a custom model id the catalog does not know gets conservative capabilities. `CredentialVault.save` validates a key by listing models, which spends no tokens. Providers also implement `prewarm()`, a credential-less `HEAD` at most once a minute; at the time of writing nothing in the app calls it.

## Design system

PIDesign holds the Ember tokens ([`EmberDesign`](../Packages/PromptImproverKit/Sources/PIDesign/Tokens/EmberDesign.swift): spacing, radii, typography, panel metrics, glass, motion, brand colours) and components such as `EButtonStyle`, `EMenuCard`, `ESelect`, `ETargetChip` and `EKeyCap`. Views use tokens, never a literal font size, radius, colour, spacing, padding, shadow or gradient, and never accent-coloured text. [`DesignSystemLintTests`](../Packages/PromptImproverKit/Tests/PIDesignTests/DesignSystemLintTests.swift) enforce this in PIDesign outside `Tokens/`, and [`PanelDesignLintTests`](../Packages/PromptImproverKit/Tests/PIAppTests/PanelUI/PanelDesignLintTests.swift) in the panel, whose own token file is `PanelLayout.swift`.

## Updates and releases

[`UpdateController`](../Packages/PromptImproverKit/Sources/PIApp/Updates/UpdateController.swift) wraps Sparkle's `SPUStandardUpdaterController`. It does not start for a Debug build, a missing or non-https `SUFeedURL`, a missing `SUPublicEDKey`, or a copy that cannot replace itself (`UpdaterSuppression`). In [`Info.plist`](../Config/Info.plist), `SUFeedURL` expands `SPARKLE_FEED_URL`, defined only in [`Release.xcconfig`](../Config/Release.xcconfig), so Debug builds have no feed; `SUPublicEDKey` comes from the project's `SPARKLE_PUBLIC_ED_KEY`; `SURequireSignedFeed` is on. The feed URL, bundle identifier and public key keep installed copies updating; do not change them.

Releases come only from [`scripts/release/release.sh`](../scripts/release/release.sh): sync feed state, resolve versions, validate invariants, archive with Developer ID, package, notarize and staple the DMG, generate the signed appcast, publish to GitHub. See [RELEASING.md](RELEASING.md).

## Testing

[`scripts/test.sh`](../scripts/test.sh) runs `swift test` on the package, passing extra arguments through (`scripts/test.sh --filter RunReducerTests`). The suites are pure logic: no network, Keychain or windows. Sessions run against fake providers and an in-memory secret store; providers run against recorded `.sse` and `.json` fixtures through [`StubURLProtocol`](../Packages/PromptImproverKit/Tests/PIProvidersTests/Support/StubURLProtocol.swift), with request bodies compared to golden JSON. The lint tests run here too.

[`LiveSmokeTests`](../Packages/PromptImproverKit/Tests/PIProvidersTests/LiveSmokeTests.swift) call the real APIs only when `PI_LIVE_ANTHROPIC_KEY` or `PI_LIVE_OPENAI_KEY` is set. Screenshot suites run only when `PI_SETTINGS_SNAPSHOTS`, `PI_GALLERY_SNAPSHOTS` or `PI_STREAM_SNAPSHOT_DIR` is set. `prompt-eval` measures quality and latency with the same `PI_LIVE_*` keys; see [EVALUATION.md](EVALUATION.md).

Debug builds accept launch flags for driving the UI without network or keys (`scripts/run.sh` forwards its arguments to the app):

| Flag | Effect |
|---|---|
| `--demo-engine` | A scripted engine streams a canned prompt, with throwaway settings, key and history. |
| `--demo-fail <case>` | The first run fails as `<case>` (`invalidKey`, `rateLimited`, `offline`, `refused`…). |
| `--demo-retry`, `--demo-setup` | The first attempt retries; or no key is stored, so the add-a-key card shows. |
| `--demo-open`, `--demo-draft <text>`, `--demo-submit`, … | Drive the demo panel to a state for screenshots. |
| `--welcome <step>` | Opens the welcome at a step (`1`–`4`, `welcome`, `key`, `shortcut`, `keys`). |
| `--welcome-language <code>`, `--welcome-tour <dir>` | The welcome in another language; a scripted tour of every step. |
| `--open-settings`, `--open-status-menu` | Open Settings or the menu bar menu after launch (`StatusItemController`). |
| `--in-memory-secrets` | Keys live in memory; the Keychain is never touched. |

The full lists live in [`PanelDemo.swift`](../Packages/PromptImproverKit/Sources/PIApp/PanelUI/Demo/PanelDemo.swift) and [`WelcomeDebug.swift`](../Packages/PromptImproverKit/Sources/PIApp/Onboarding/WelcomeDebug.swift).
