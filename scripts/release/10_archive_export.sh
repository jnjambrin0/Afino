#!/usr/bin/env bash
# Stage: archive and export. Archives the Release configuration for any Mac into build/release/
# and exports it signed with Developer ID (export-options-developer-id.plist). Needs xcodebuild
# and the Developer ID identity in the login keychain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_release_config
load_release_state

require_cmd "$XCODEBUILD_BIN"

archive_path="${ARCHIVE_PATH:-$REPO_ROOT/build/release/$APP_NAME.xcarchive}"
export_path="${EXPORT_PATH:-$REPO_ROOT/build/release/export}"
export_options_plist="${EXPORT_OPTIONS_PLIST:-$SCRIPT_DIR/export-options-developer-id.plist}"

build_xcode_version_override_args

mkdir -p "$(dirname "$archive_path")" "$export_path"

[[ -f "$export_options_plist" ]] || die "Missing export options: $export_options_plist"

"$XCODEBUILD_BIN" \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$archive_path" \
  -derivedDataPath "$RELEASE_DERIVED_DATA" \
  -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO \
  "${XCODE_VERSION_OVERRIDE_ARGS[@]}" \
  archive

"$XCODEBUILD_BIN" \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options_plist"

app_path="$export_path/$APP_NAME.app"
[[ -d "$app_path" ]] || die "Exported app not found at $app_path"

write_release_state RELEASE_ARCHIVE_PATH "$archive_path"
write_release_state RELEASE_EXPORT_PATH "$export_path"
write_release_state RELEASE_EXPORTED_APP_PATH "$app_path"

log "Archive/export completed: $app_path"
