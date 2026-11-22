# Releasing

Every copy of Afino that users run comes from one pipeline, [`scripts/release/release.sh`](../scripts/release/release.sh). It archives a Developer ID build, packages it in a notarized and stapled disk image, adds it to the signed Sparkle feed, and publishes both. This page describes what it needs, what each stage does, and the rules that keep installed copies updating.

## The rules

- **Only the pipeline makes builds under the release bundle identifier** (`com.jnjambrin0.PromptImprover`). The Keychain ties each stored API key to the Developer ID signature that saved it, so an ad-hoc or development-signed copy with that identifier would make the Keychain prompt for every key. Debug builds, and `scripts/build.sh Release`, use `com.jnjambrin0.PromptImprover.dev` and have no update feed.
- **The bundle identifier, the feed URL and the Sparkle public key never change.** Installed copies look for updates at `https://jnjambrin0.github.io/Afino/updates/stable/appcast.xml` and accept only updates signed with the key they were built with. The feed URL is set once, in [`Config/Release.xcconfig`](../Config/Release.xcconfig); the public key is the `SPARKLE_PUBLIC_ED_KEY` build setting of the project.
- **Published feed items are never removed or changed.** A Mac that cannot run the newest version keeps receiving the newest one it can. The pipeline checks this on every run. (The feed was started afresh at 1.0.2, when the repository took the name Afino; builds before it looked at another address and are not in it.)

## Prerequisites

On the Mac that releases:

| What | How |
|---|---|
| macOS 26 and Xcode 27.2 at `/Applications/Xcode.app` | The path is `XCODEBUILD_BIN` in [`release-config.env`](../scripts/release/release-config.env). |
| A **Developer ID Application** certificate with its private key in the login keychain | `security find-identity -v -p codesigning` must list the identity named by `DEVELOPER_ID_APPLICATION`; its team is `DEVELOPMENT_TEAM_ID`. |
| A **notarytool keychain profile** | Created once with `xcrun notarytool store-credentials AC_NOTARY` (an App Store Connect API key, or an Apple ID with an app-specific password). The name is `NOTARY_PROFILE`. |
| The **Sparkle EdDSA private key** in the login keychain | See below. |
| `gh`, signed in with push access to the repository; `git` with the GitHub repository as `origin`; `python3`; `rsync` | `gh auth status` should succeed. |

The first run also creates a Python virtual environment in `build/.dmgbuild-venv` and installs [dmgbuild](https://github.com/dmgbuild/dmgbuild) into it, which needs the network once.

### The Sparkle signing key

Sparkle verifies every update, and the feed itself, with an Ed25519 signature. The private key lives in the login keychain under the account `ed25519` (override with `SPARKLE_KEY_ACCOUNT`), where Sparkle's `generate_keys` tool created it; its public half is the `SPARKLE_PUBLIC_ED_KEY` build setting, which the build writes into `SUPublicEDKey`. Before signing anything, the appcast stage checks that the keychain key is the private half of the app's public key.

Treat the key as irreplaceable. Every installed copy trusts only the public key it shipped with, so an update signed with a new key is rejected by all of them, and their users would have to download Afino again by hand. Rotate it only for a compromise, and only with a plan for that. Keep an encrypted backup (`generate_keys -x <file>` exports it, `-f <file>` imports it on another Mac). On a machine without the key in its keychain, `SPARKLE_PRIVATE_KEY_BASE64` can carry it instead.

The Sparkle tools come from the release build itself (`build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`), so they always match the Sparkle version the app links. `SPARKLE_BIN` in `release-config.env` can point elsewhere.

## Versions

Nothing is edited by hand. The pipeline derives both numbers:

- **Version** (`CFBundleShortVersionString`): the tag without its `v`. Tags are `vX`, `vX.Y` or `vX.Y.Z`.
- **Build number** (`CFBundleVersion`, Sparkle's `sparkle:version`): the highest build number in the published feed plus one. With no feed yet it is `1`.

They are passed to `xcodebuild` as `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, overriding the values in the project, which only matter for Debug builds. 1.0.0 was build 7 and 1.0.1 build 8.

## Making a release

1. Make sure `main` is what you want to ship: `scripts/test.sh` and `scripts/build.sh` pass, and the change is described in [CHANGELOG.md](../CHANGELOG.md).
2. Tag it and create the GitHub release with its notes. The pipeline uploads the disk image to this release, so it must exist:

   ```bash
   git tag v1.0.2 && git push origin v1.0.2
   gh release create v1.0.2 --verify-tag --title "Afino 1.0.2" --notes-file notes.md
   ```

3. From a checkout of that tag, run the pipeline:

   ```bash
   scripts/release/release.sh                         # finds the tag with git describe
   RELEASE_TAG=v1.0.2 scripts/release/release.sh      # or names it
   SKIP_PUBLISH=1 scripts/release/release.sh          # everything except publishing

`RELEASE_MIN_BUILD=<n>` sets a floor for the build number, which is otherwise one more than the highest build in the feed. It exists for the rare case where the feed has been started afresh.
   ```

   It takes a few minutes, most of them waiting for Apple's notary service. Each stage logs its start and its duration.

4. Check the result: the release on GitHub has `Afino-v1.0.2.dmg`, the [feed](https://jnjambrin0.github.io/Afino/updates/stable/appcast.xml) lists the new build first (GitHub Pages can take a minute), and an installed copy finds the update with **Check for Updates** in Settings › About.

`SKIP_PUBLISH=1` runs every stage up to and including the signed appcast and stops there: the notarized disk image and the new `appcast.xml` are left in `updates/stable/` to inspect, and nothing is uploaded or pushed. The next run starts again from the published feed, so a skipped run leaves nothing behind in it.

## The stages

`release.sh` runs these scripts in this order. They share their results through `scripts/release/.release-state.env` (git-ignored), which `release.sh` empties at the start, so after a failure a single stage can be run again on its own, for example `scripts/release/40_publish_github.sh`.

| Stage | Script | What it does |
|---|---|---|
| Sync the feed | [`05_sync_feed_state.sh`](../scripts/release/05_sync_feed_state.sh) | Fetches the `gh-pages` branch and mirrors its `updates/stable/` into the local `updates/stable/` (git-ignored on `main`). Without that branch it starts an empty feed. |
| Resolve versions | [`06_resolve_release_versions.sh`](../scripts/release/06_resolve_release_versions.sh) | Reads the tag (`RELEASE_TAG` or `git describe --tags --exact-match`), checks its format, and computes the version and build number described above. |
| Validate invariants | [`00_validate_invariants.sh`](../scripts/release/00_validate_invariants.sh) | Reads the Release build settings with those numbers and stops unless the bundle identifier is `com.jnjambrin0.PromptImprover`, the feed URL is the HTTPS one in `release-config.env`, the public key is a 32-byte Ed25519 key, and the build number is higher than every published one. |
| Archive and export | [`10_archive_export.sh`](../scripts/release/10_archive_export.sh) | `xcodebuild archive` for any Mac (Apple silicon and Intel) into `build/release/`, then `-exportArchive` with [`export-options-developer-id.plist`](../scripts/release/export-options-developer-id.plist) (Developer ID, manual signing). The project itself turns on the hardened runtime and secure timestamps for Release. |
| Package and notarize | [`20_package_dmg_notarize_staple.sh`](../scripts/release/20_package_dmg_notarize_staple.sh) | Checks that the notary profile works, then verifies the app's signature and every Mach-O file inside it (our Developer ID and team, a secure timestamp, the hardened runtime, no `get-task-allow`). Builds `updates/stable/Afino-<build>.dmg` with dmgbuild from [`dmg-settings.py`](../scripts/release/dmg-assets/dmg-settings.py) and the background in `dmg-assets/`, verifies and signs it, submits it to the notary service and waits, staples the ticket, and requires Gatekeeper to report the app as `Notarized Developer ID`. |
| Sign the appcast | [`30_generate_signed_appcast.sh`](../scripts/release/30_generate_signed_appcast.sh) | Checks the signing key against the app's public key, then runs Sparkle's `generate_appcast` over `updates/stable/` without binary deltas (`APPCAST_MAXIMUM_DELTAS`, default 0). It then compares the new feed with the published one: the new item must require the app's `LSMinimumSystemVersion`, and every published item must still be there with its minimum system version unchanged. Finally it validates the invariants again, now requiring the new build in the feed with the right version. |
| Publish | [`40_publish_github.sh`](../scripts/release/40_publish_github.sh) | Skipped with `SKIP_PUBLISH=1`. Uploads the disk image to the GitHub release as `Afino-<tag>.dmg` (removing any build-numbered copy), then commits `updates/stable/` to the `gh-pages` branch, which GitHub Pages serves as the feed. |

`generate_appcast` and the publishing commands stop after 15 minutes (`APPCAST_TIMEOUT_SECONDS`, `PUBLISH_TIMEOUT_SECONDS`).

## Configuration

[`scripts/release/release-config.env`](../scripts/release/release-config.env) holds the project, scheme, app name, expected bundle identifier, feed URL, repository, Pages branch, signing identity, team, notary profile and paths. It is read by every stage and its values win over the environment, so change them in the file. These can be set in the environment instead:

| Variable | Effect |
|---|---|
| `RELEASE_TAG` | The tag to release, when the checkout is not exactly on it. |
| `SKIP_PUBLISH=1` | Stop before publishing. |
| `SPARKLE_KEY_ACCOUNT` | The keychain account of the Sparkle key (default `ed25519`). |
| `SPARKLE_PRIVATE_KEY_BASE64` | The Sparkle private key itself, instead of the keychain. |
| `APPCAST_MAXIMUM_DELTAS` | Binary deltas to generate per update (default 0). |
| `APPCAST_TIMEOUT_SECONDS`, `PUBLISH_TIMEOUT_SECONDS` | Time limits (default 900 each). |
| `RELEASE_CONFIG_FILE` | Another configuration file. |

The disk image's window, its background (made by [`design/render-dmg-background.swift`](../design/render-dmg-background.swift)) and its icon positions are described in [BRAND.md](BRAND.md#installer-window).
