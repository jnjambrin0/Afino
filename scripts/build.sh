#!/bin/bash
# Builds the Afino app and prints only diagnostics and the result.
#   scripts/build.sh            Debug (default)
#   scripts/build.sh Release    optimised build, for performance measurements only
# DerivedData lives inside the checkout (build/DerivedData, or PI_DERIVED_DATA), so every git
# worktree gets its own. Needs Xcode 27.2 or later. Distribution builds are made by
# scripts/release/release.sh, never by this script.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-Debug}"
DERIVED="${PI_DERIVED_DATA:-$PWD/build/DerivedData}"
LOG="$DERIVED/last-build.log"
mkdir -p "$DERIVED"

# Debug builds are com.jnjambrin0.PromptImprover.dev: their own preferences, history and Keychain
# items, apart from an installed release. A measurement build keeps that identity and the
# development signature, and has no update feed. A build under the release identifier must only
# ever come from the release pipeline: an ad-hoc or development-signed copy there would make the
# Keychain prompt for every stored API key.
OVERRIDES=()
if [ "$CONFIGURATION" = Release ]; then
  OVERRIDES=("PI_RELEASE_SIGNING_IDENTITY=Apple Development" CODE_SIGN_STYLE=Automatic SPARKLE_FEED_URL= PI_BUNDLE_IDENTIFIER_SUFFIX=.dev)
fi

if xcodebuild -project PromptImprover.xcodeproj -scheme PromptImprover -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' ${OVERRIDES[@]+"${OVERRIDES[@]}"} \
    build >"$LOG" 2>&1; then
  grep -E "warning: " "$LOG" | grep -v -E "appintentsmetadataprocessor|Run script build phase" \
    | sed -E "s|$PWD/||" | sort -u | cut -c1-260 | head -30 || true
  APP="$DERIVED/Build/Products/$CONFIGURATION/Afino.app"
  echo "BUILD OK → $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"))"
else
  grep -E "error: " "$LOG" | sed -E "s|$PWD/||" | sort -u | cut -c1-320 | head -40 || true
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi
