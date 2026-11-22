# Security policy

Afino handles API keys and the text people write, so security reports are taken seriously. This page says what is in scope, how Afino is meant to behave, and how to report a problem privately.

## Supported versions

Security fixes go into the latest release. Afino updates itself, so the fix reaches every copy on macOS 26 or later. PromptImprover 0.x is no longer maintained.

## How Afino handles secrets and data

Knowing the intended behaviour helps tell a vulnerability from a design decision:

- **API keys** are stored in the login Keychain as generic passwords (service `com.jnjambrin0.PromptImprover.apikeys`), readable after first unlock, on this device only and never synced. Access is tied to the app's Developer ID signature. A key is sent only to the provider it belongs to, over HTTPS, and is redacted from errors and logs.
- **Drafts and results** travel only between the Mac and the provider the user chose. There is no Afino server and no analytics. OpenAI requests are sent with `store: false`.
- **History** (optional, the last 50 improvements) is a plain-text file in `~/Library/Application Support/com.jnjambrin0.PromptImprover/`, readable only by the user (`0600` in a `0700` folder).
- **Logs** use the unified logging system and record sizes, status codes and request identifiers, never drafts, results, request bodies or keys.
- **The app** is not sandboxed. Releases are signed with a Developer ID, use the hardened runtime and are notarized by Apple. Updates come from a Sparkle feed that is itself signed, and every update is verified with an EdDSA signature before it is installed.
- **A draft is text to rewrite**, never instructions to the app or the engine. Prompt injection that makes the engine reveal its instructions, obey the draft or leak data is in scope.

Reports about a key being written to disk or a log, sent to the wrong host, or readable by another user are especially welcome.

## Scope

- The source code in this repository.
- The release tooling in `scripts/release/`.
- Official release artifacts: the disk images on the [releases page](https://github.com/jnjambrin0/Afino/releases) and the update feed at `jnjambrin0.github.io/Afino`.

The providers' own services (Anthropic, OpenAI) and Sparkle itself are out of scope; report those to their maintainers.

## Reporting a vulnerability

Report privately through GitHub: **[Report a vulnerability](https://github.com/jnjambrin0/Afino/security/advisories/new)**. Please do not open a public issue or pull request for a security problem.

Include as much of this as you can:

- The Afino version (Settings › About) or commit, and the macOS version.
- What an attacker can do, and how severe you think it is.
- Steps to reproduce, and a proof of concept if it is safe to share.
- The engine provider and model, if it matters.
- Any fix you would suggest.

Never include a real API key. If you need to show one, use a revoked key or a placeholder.

## What happens next

On a best-effort basis:

- An acknowledgement within 3 business days.
- Validation and an assessment of severity, then updates while a fix is prepared.
- A coordinated release, and a security advisory describing the impact, the affected versions and the fix.

Please keep the details private until a fix or mitigation is published.

## Safe harbour

If you act in good faith and follow this policy, we will not pursue action against research that avoids privacy violations, data destruction and service disruption, does not access or change data beyond what is needed to show the issue, and is reported promptly and privately.
