#!/usr/bin/env bash
# Makes a release of Afino: a Developer ID build in a notarized, stapled disk image, added to the
# signed Sparkle feed and published to GitHub. See docs/RELEASING.md.
#
#   scripts/release/release.sh                      # from a checkout of the release tag
#   RELEASE_TAG=v1.2.3 scripts/release/release.sh   # names the tag
#   SKIP_PUBLISH=1 scripts/release/release.sh       # everything except uploading and pushing
#
# Needs the Developer ID identity, the notarytool profile and the Sparkle key named in
# release-config.env, plus gh, git, python3 and rsync. The GitHub release for the tag must exist.
# The stages share their results through .release-state.env, which this script empties first;
# after a failure, a single stage can be run again on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
reset_release_state

run_stage() {
  local label="$1"
  local start_ts end_ts elapsed
  shift
  start_ts="$(date +%s)"
  log "Starting stage: $label"
  "$@"
  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"
  log "Completed stage: $label (${elapsed}s)"
}

run_stage "sync_feed_state" "$SCRIPT_DIR/05_sync_feed_state.sh"
run_stage "resolve_release_versions" "$SCRIPT_DIR/06_resolve_release_versions.sh"
run_stage "validate_invariants" "$SCRIPT_DIR/00_validate_invariants.sh"
run_stage "archive_export" "$SCRIPT_DIR/10_archive_export.sh"
run_stage "package_notarize_staple" "$SCRIPT_DIR/20_package_dmg_notarize_staple.sh"
run_stage "generate_signed_appcast" "$SCRIPT_DIR/30_generate_signed_appcast.sh"

if [[ "${SKIP_PUBLISH:-0}" != "1" ]]; then
  run_stage "publish_github" "$SCRIPT_DIR/40_publish_github.sh"
else
  log "SKIP_PUBLISH=1, skipping GitHub publication."
fi

log "Release pipeline completed successfully."
