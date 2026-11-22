#!/usr/bin/env bash
# Stage: sign the appcast. Checks that the Sparkle key in the keychain (or SPARKLE_PRIVATE_KEY_BASE64)
# matches the app's public key, runs Sparkle's generate_appcast over updates/stable/, checks that
# every published item survives with its minimum system version, and validates the invariants
# again with the new build in the feed. Needs the Sparkle tools from the release build and python3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_var RELEASE_BUILD_VERSION
require_var RELEASE_SHORT_VERSION

resolve_sparkle_bin

appcast_generator="$SPARKLE_BIN/generate_appcast"
[[ -x "$appcast_generator" ]] || die "Missing executable Sparkle generator at $appcast_generator"

mkdir -p "$UPDATES_DIR"
appcast_path="$UPDATES_DIR/appcast.xml"

# The update is only accepted by installed copies when it is signed with the private half of the
# key they were built with. Check that before signing anything.
if [[ -z "${SPARKLE_PRIVATE_KEY_BASE64:-}" ]]; then
  require_var RELEASE_EXPORTED_APP_PATH
  app_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$RELEASE_EXPORTED_APP_PATH/Contents/Info.plist")"
  keychain_public_key="$("$SPARKLE_BIN/generate_keys" --account "${SPARKLE_KEY_ACCOUNT:-ed25519}" -p 2>/dev/null)" \
    || die "There is no Sparkle signing key for the account '${SPARKLE_KEY_ACCOUNT:-ed25519}' in the keychain."
  [[ "$app_public_key" == "$keychain_public_key" ]] \
    || die "The app's SUPublicEDKey is not the public half of the keychain signing key: installed copies would reject this update."
fi

# 05_sync_feed_state.sh left the published feed here. Keep a copy to prove that every published
# item survives: copies on an older macOS still need theirs.
published_snapshot="$(mktemp)"
trap 'rm -f "$published_snapshot"' EXIT
if [[ -f "$appcast_path" ]]; then cp "$appcast_path" "$published_snapshot"; else : >"$published_snapshot"; fi

# No binary deltas by default: a delta from a 0.x build to the rewritten, differently signed 1.x
# app has no value. Raise APPCAST_MAXIMUM_DELTAS once 1.x releases follow each other.
appcast_args=(--maximum-deltas "${APPCAST_MAXIMUM_DELTAS:-0}")
timeout_seconds="${APPCAST_TIMEOUT_SECONDS:-900}"
start_ts="$(date +%s)"

if [[ -n "${SPARKLE_PRIVATE_KEY_BASE64:-}" ]]; then
  log "Generating signed appcast using SPARKLE_PRIVATE_KEY_BASE64 (timeout ${timeout_seconds}s)."
  (
    echo "$SPARKLE_PRIVATE_KEY_BASE64" | base64 --decode | "$appcast_generator" --ed-key-file - "${appcast_args[@]}" "$UPDATES_DIR"
  ) &
else
  log "Generating signed appcast using Sparkle key from Keychain (timeout ${timeout_seconds}s)."
  (
    "$appcast_generator" --account "${SPARKLE_KEY_ACCOUNT:-ed25519}" "${appcast_args[@]}" "$UPDATES_DIR"
  ) &
fi
generator_pid="$!"

while kill -0 "$generator_pid" >/dev/null 2>&1; do
  elapsed="$(( $(date +%s) - start_ts ))"
  if (( elapsed > timeout_seconds )); then
    log "generate_appcast exceeded timeout (${timeout_seconds}s). Sending SIGTERM."
    kill "$generator_pid" >/dev/null 2>&1 || true
    sleep 2
    kill -9 "$generator_pid" >/dev/null 2>&1 || true
    wait "$generator_pid" 2>/dev/null || true
    die "generate_appcast timed out after ${timeout_seconds}s"
  fi
  sleep 1
done
set +e
wait "$generator_pid"
generator_status="$?"
set -e
if [[ "$generator_status" -ne 0 ]]; then
  die "generate_appcast failed with exit code $generator_status"
fi

elapsed_total="$(( $(date +%s) - start_ts ))"
log "generate_appcast completed in ${elapsed_total}s."

[[ -f "$appcast_path" ]] || die "Expected appcast at $appcast_path"

expected_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${RELEASE_EXPORTED_APP_PATH:?}/Contents/Info.plist")"
python3 - "$appcast_path" "$published_snapshot" "$RELEASE_BUILD_VERSION" "$expected_minimum" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

appcast_path, published_path, build_number, expected_minimum = sys.argv[1:5]
sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ns = {"sparkle": sparkle_ns}

def items(path):
    result = {}
    for item in ET.parse(path).getroot().findall("./channel/item"):
        enclosure = item.find("enclosure")
        version = item.findtext("sparkle:version", "", ns) or (
            enclosure.attrib.get(f"{{{sparkle_ns}}}version", "") if enclosure is not None else ""
        )
        result[version] = item.findtext("sparkle:minimumSystemVersion", "", ns)
    return result

generated = items(appcast_path)
if generated.get(build_number) != expected_minimum:
    sys.exit(f"[release] ERROR: appcast item {build_number} has minimumSystemVersion {generated.get(build_number)!r}, expected {expected_minimum!r}")

if os.path.getsize(published_path) > 0:
    for version, minimum in items(published_path).items():
        if version == build_number:
            continue
        if version not in generated:
            sys.exit(f"[release] ERROR: published appcast item {version} is missing from the generated feed")
        if generated[version] != minimum:
            sys.exit(f"[release] ERROR: appcast item {version} changed its minimum system version from {minimum!r} to {generated[version]!r}")
print(f"[release] Appcast keeps {len(generated) - 1} earlier item(s) and requires macOS {expected_minimum} for build {build_number}")
PY

"$SCRIPT_DIR/00_validate_invariants.sh" --require-current-in-appcast

write_release_state RELEASE_APPCAST_PATH "$appcast_path"
log "Signed appcast generated: $appcast_path"
