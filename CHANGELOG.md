# Changelog

All notable changes to Afino are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release, with its disk image, is on the [releases page](https://github.com/jnjambrin0/Afino/releases).

## [Unreleased]

## [1.0.2] - 2026-11-22

### Changed

- **Update feed.** The repository is now `jnjambrin0/Afino`, and Afino looks for updates there. Earlier builds looked at the old address and cannot update themselves: install 1.0.2 from the releases page.
- A new README with screenshots, and guides to the architecture and the release process.

### Fixed

- **History.** A result rewritten for another model keeps its own target, so reopening it from the history and refining an earlier version addresses the right model.

## [1.0.1] - 2026-11-21

### Fixed

- **Installer window.** The disk image said "Drag PromptImprover to Applications". It now says Afino, and its background reads well with Finder in light and dark mode.
- **Menu bar menu.** The menu is now the standard macOS menu, with its real keyboard shortcuts.
- **Settings › About.** "Show welcome again" opens the welcome right away, and now says so.

## [1.0.0] - 2026-11-21

PromptImprover is now **Afino**, rewritten from the ground up. Press a shortcut, type a rough idea, get a prompt worth sending: the improved prompt streams into a small dark glass panel and is copied to your clipboard.

### Added

- **Direct API, your own key.** Afino talks to Anthropic or OpenAI directly with your API key, stored in your Mac's Keychain.
- **A new panel.** Open it from anywhere with ⌃⌥P, type or paste, pick who the prompt is for (Claude, ChatGPT, Gemini or any model) with Tab, and press Return.
- **Refine in place.** Type "shorter" or "add an example" on a result, regenerate it, step between versions, or rewrite the same draft for another model.
- **A rewrite that stays faithful.** Afino writes the prompt and never carries out the task. Your facts, code and template variables are kept exactly, and it leaves a short fill-in such as `[audience]` instead of inventing details.
- A welcome on first launch; Settings for the engine, keys, custom instructions and shortcuts; and a local history of your last 50 improvements.
- A new icon and colours, and releases signed with a Developer ID and notarized by Apple.

### Changed

- Afino requires **macOS 26 or later**. On earlier systems the app stays on the last 0.x release.
- The default shortcut changed from ⌘⌥I to ⌃⌥P.
- The app updates itself from 0.x. Its file in Applications may keep the name `PromptImprover.app`; Finder shows it as Afino.

### Removed

- The `codex` and `claude` command-line tools are no longer used, and the guide editor and the JSON output contract are gone. Guides you imported or edited in 0.x are kept in `~/Library/Application Support/com.jnjambrin0.PromptImprover/Legacy-0.x`.

### Known limits

- For image-generation requests the rewrite can still add a detail you did not ask for (a background or composition). Check the result before sending.

## 0.x

PromptImprover 0.x drove the `codex` and `claude` command-line tools. Its releases are on the [releases page](https://github.com/jnjambrin0/Afino/releases?q=v0&expanded=true).

[Unreleased]: https://github.com/jnjambrin0/Afino/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/jnjambrin0/Afino/releases/tag/v1.0.2
[1.0.1]: https://github.com/jnjambrin0/Afino/releases/tag/v1.0.1
[1.0.0]: https://github.com/jnjambrin0/Afino/releases/tag/v1.0.0
