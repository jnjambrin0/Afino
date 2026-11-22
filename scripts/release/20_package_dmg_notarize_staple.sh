#!/usr/bin/env bash
# Stage: package and notarize. Verifies the signature of the exported app and of every Mach-O file
# in it, builds updates/stable/<app>-<build>.dmg with dmgbuild (dmg-assets/), signs it, has Apple
# notarize it, staples the ticket and checks Gatekeeper's verdict. Needs the Developer ID identity,
# the notarytool keychain profile, hdiutil, spctl and python3 (for dmgbuild).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd hdiutil
require_cmd codesign
require_cmd spctl
require_cmd xcrun

require_var RELEASE_EXPORTED_APP_PATH
require_var RELEASE_BUILD_VERSION
require_var DEVELOPER_ID_APPLICATION
require_var NOTARY_PROFILE

app_path="$RELEASE_EXPORTED_APP_PATH"
[[ -d "$app_path" ]] || die "Missing exported app: $app_path"

# Fail before the slow steps when the notary credentials are missing.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "No notarytool keychain profile named '$NOTARY_PROFILE'. Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE"

# Every Mach-O file inside the app: our Developer ID, our team, a secure timestamp; executables
# also with the hardened runtime; nothing with get-task-allow (notarization refuses it). Sparkle's
# nested helpers are the usual place for this to go wrong.
verify_code_files() {
  local file kind details problems=0 count=0
  while IFS= read -r -d '' file; do
    kind="$(file -b "$file")"
    [[ "$kind" == Mach-O* ]] || continue
    count=$((count + 1))
    local name="${file#"$app_path"/}" issues=()
    if ! details="$(codesign -dvv "$file" 2>&1)"; then
      issues+=("unsigned")
    else
      grep -q "^Authority=Developer ID Application: .*($DEVELOPMENT_TEAM_ID)$" <<<"$details" || issues+=("not signed with our Developer ID")
      grep -q "^TeamIdentifier=$DEVELOPMENT_TEAM_ID$" <<<"$details" || issues+=("team is not $DEVELOPMENT_TEAM_ID")
      grep -q "^Timestamp=" <<<"$details" || issues+=("no secure timestamp")
      if [[ "$kind" == *executable* ]] && ! grep -q "flags=.*runtime" <<<"$details"; then
        issues+=("no hardened runtime")
      fi
      if codesign -d --entitlements - --xml "$file" 2>/dev/null | grep -q "get-task-allow"; then
        issues+=("has get-task-allow")
      fi
    fi
    if [[ ${#issues[@]} -gt 0 ]]; then
      problems=$((problems + 1))
      log "FAIL  $name: $(IFS=,; echo "${issues[*]}")"
    fi
  done < <(find "$app_path" -type f -print0)
  [[ "$problems" -eq 0 ]] || die "$problems of $count code files are not signed as they should be"
  log "$count code files, all signed by team $DEVELOPMENT_TEAM_ID with a secure timestamp"
}

codesign --verify --deep --strict --verbose=2 "$app_path"
verify_code_files

ensure_dmgbuild

mkdir -p "$UPDATES_DIR"
dmg_path="$UPDATES_DIR/$APP_NAME-$RELEASE_BUILD_VERSION.dmg"

"$DMGBUILD" \
  -s "$DMG_ASSETS_DIR/dmg-settings.py" \
  -D app="$app_path" \
  -D background="$DMG_ASSETS_DIR/dmg-background.tiff" \
  "$APP_NAME" \
  "$dmg_path"

hdiutil verify "$dmg_path"

codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg_path"

xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

# The app itself is not stapled (the DMG is): Gatekeeper checks its ticket online here.
assessment="$(spctl --assess --type execute -vv "$app_path" 2>&1 || true)"
log "$assessment"
grep -q "source=Notarized Developer ID" <<<"$assessment" || die "Gatekeeper does not accept the app as notarized"

write_release_state RELEASE_DMG_PATH "$dmg_path"
log "DMG packaged, notarized, and stapled: $dmg_path"
