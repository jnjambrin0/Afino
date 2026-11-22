#!/bin/bash
# Installs the last build of scripts/build.sh as ~/Applications/Afino Dev.app and launches it
# through LaunchServices, the way a user would. Arguments are passed to the app, e.g.
#   scripts/run.sh --demo-engine --demo-open --demo-draft "a snake game" --demo-submit
#   ANTHROPIC_API_KEY=… scripts/run.sh      (a Debug build then takes its keys from the environment)
# PI_CONFIGURATION=Release selects the optimised build made by `scripts/build.sh Release`;
# PI_DERIVED_DATA picks the DerivedData folder, as for scripts/build.sh.
#
# These builds are com.jnjambrin0.PromptImprover.dev: only the copy installed here is stopped,
# never a release of Afino that may be running as well.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${PI_DERIVED_DATA:-$PWD/build/DerivedData}/Build/Products/${PI_CONFIGURATION:-Debug}/Afino.app"
DESTINATION="$HOME/Applications/Afino Dev.app"

[ -d "$SOURCE" ] || { echo "No build at $SOURCE — run scripts/build.sh first" >&2; exit 1; }

if pkill -f "^$DESTINATION/Contents/MacOS/Afino( |$)" 2>/dev/null; then sleep 0.4; fi
rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
ditto "$SOURCE" "$DESTINATION"
open -n "$DESTINATION" --args "$@"
echo "Launched $DESTINATION ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist"))"
