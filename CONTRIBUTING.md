# Contributing to Afino

Thanks for your interest in Afino. Bug reports, fixes, documentation, tests and well-argued ideas are all welcome. This guide covers how to set up, how to check your work, and what a good pull request looks like.

All participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

1. Search the [issues](https://github.com/jnjambrin0/Afino/issues) and open pull requests for the same thing.
2. For anything bigger than a small fix, open an issue (or comment on one) first, so we can agree on the approach before you spend time on it.
3. Keep each change to one problem. Unrelated refactors belong in their own pull request.

Security problems are never reported in public issues; see [SECURITY.md](SECURITY.md).

## Setting up

You need macOS 26 or later and Xcode 27.2 or later (the project uses Xcode's JSON project format). Clone the repository and run:

```bash
scripts/test.sh     # unit tests of the Swift package
scripts/build.sh    # Debug build of the app; prints only warnings, errors and the result
scripts/run.sh      # installs that build as ~/Applications/Afino Dev.app and launches it
```

The app target in `PromptImprover/` is a shell; the code lives in the Swift package `Packages/PromptImproverKit`. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the modules and how a request flows through them.

Debug builds have their own bundle identifier (`com.jnjambrin0.PromptImprover.dev`), so they never touch an installed release's settings, history or Keychain items, and they never look for updates. To try one with a real key without the project's signing certificate, pass the key in the environment instead of the Keychain:

```bash
ANTHROPIC_API_KEY=… scripts/run.sh        # or OPENAI_API_KEY, or both
```

To work on the interface without a key or a network, a Debug build can drive itself with a scripted engine, for example `scripts/run.sh --demo-engine --demo-open --demo-draft "a snake game" --demo-submit`. Every flag is listed in [`PanelDemo.swift`](Packages/PromptImproverKit/Sources/PIApp/PanelUI/Demo/PanelDemo.swift) and [`WelcomeDebug.swift`](Packages/PromptImproverKit/Sources/PIApp/Onboarding/WelcomeDebug.swift); add `--in-memory-secrets` to keep the Keychain out entirely.

## Checking your work

There is no CI: the checks run on your Mac, and a pull request should say which ones you ran.

| Check | When |
|---|---|
| `scripts/test.sh` | Always. Pure logic only: no network, no Keychain, no windows. Pass `swift test` options through, e.g. `scripts/test.sh --filter RunReducerTests`. |
| `scripts/build.sh` | Always. The build should add no warnings. |
| `scripts/run.sh` and a look at the change | Any change to the panel, Settings, the welcome or the menu bar. Include screenshots in light and dark where it applies. |
| `prompt-eval smoke` | Any change to the engine prompt (`core.txt`), a target pack, the composer or a provider client. Attach the summary. See [docs/EVALUATION.md](docs/EVALUATION.md). |

The test suite includes lint tests that enforce the module graph and the design rules below, so a failing lint test is usually a pointer to the convention you hit.

Two kinds of tests call the real APIs and spend your own credit, so they run only when you set dedicated keys (deliberately not `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`):

```bash
PI_LIVE_ANTHROPIC_KEY=… PI_LIVE_OPENAI_KEY=… swift test --package-path Packages/PromptImproverKit --filter LiveSmokeTests
PI_LIVE_ANTHROPIC_KEY=… swift run --package-path Packages/PromptImproverKit prompt-eval smoke
```

## Conventions

- Swift 6 language mode, with `@Observable` rather than `ObservableObject`.
- No singletons: services are built once in `AppDelegate` and passed down by initializer.
- Modules only depend on the layers below them (`Package.swift` lists the graph).
- Views use the design tokens and components in `PIDesign`: no literal colours, radii, spacing, fonts or durations. The brand accent marks only the primary action, the caret and the "Copied" check ([docs/BRAND.md](docs/BRAND.md)).
- Never log, store or print a draft, a result, a request body or an API key. Log sizes, counts, status codes and request identifiers.
- User-facing text lives in the string catalogs (`*.xcstrings`) and is translated into English and Spanish.
- Keep wording plain and short, in the voice of the existing interface.

If you change the interface in a way that makes the README screenshots out of date, say so in the pull request; [docs/BRAND.md](docs/BRAND.md#screenshots) explains how they are regenerated.

## Pull requests

1. Fork the repository and branch from `main`.
2. Make a focused change, with tests when behaviour changes and documentation when something user-visible changes.
3. Run the checks above.
4. Open the pull request with the template, and link the issue it resolves (`Closes #123`).

Maintainers review on a best-effort basis. Review comments and requests for changes are a normal part of the process; a pull request is merged when its scope, quality and verification are clear.

Releases are made by the maintainer with the signed pipeline in `scripts/release/` ([docs/RELEASING.md](docs/RELEASING.md)); contributors never need it.

## Licence of contributions

By submitting a contribution you agree that it is provided under the project's licence, the [Apache License 2.0](LICENSE). No CLA or DCO sign-off is required.
