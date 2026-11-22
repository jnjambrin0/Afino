#!/bin/bash
# Captures the raw screenshots behind the README images from a Debug build that drives itself:
# the scripted demo engine (no network, no API key, no Keychain) puts the panel in each state.
#
#   scripts/build.sh                          # a Debug build (the demo flags exist only in Debug)
#   design/capture-screenshots.sh [scene…]    # result target-menu refine history settings-engine
#                                             # (all of them when none is named)
#   xcrun swift design/render-doc-images.swift
#
# Writes build/screenshots/<scene>.png: the window alone, without its shadow, at the display's
# scale. Needs a logged-in session with the screen unlocked; the first run asks for Screen
# Recording permission for the terminal.
#
# The build is copied to build/screenshots/ under its own bundle identifier
# (com.jnjambrin0.PromptImprover.screenshots) and signed ad hoc, so it never meets a copy of Afino
# that is already running, nor its settings, history or Keychain items. That copy and its
# preferences are deleted at the end. Each scene opens the panel, which takes the keyboard focus for
# a few seconds: leave the Mac alone while it runs. A scene whose window lost focus (and closed)
# is reported, so it can be taken again.
#
# PI_DERIVED_DATA picks the build, as for scripts/build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${PI_DERIVED_DATA:-$PWD/build/DerivedData}/Build/Products/Debug/Afino.app"
OUT="$PWD/build/screenshots"
APP="$OUT/Afino Screenshots.app"
DOMAIN="com.jnjambrin0.PromptImprover.screenshots"
# A rough draft that already holds every requirement, so the canned result reads as what Afino
# does: the same request, made clear. (The demo engine answers every draft with the same prompt.)
DRAFT="act as a senior frontend dev who makes small polished browser games. snake in ONE html file, no libs. arrows or wasd, eat food to grow, you lose if you hit a wall or yourself. 20x20 grid on a canvas, crisp on retina. a bit faster every 5 food. score + best score (localStorage). space pauses, enter restarts after game over. readable code: separate bits for state, rendering, input. calm dark colours, 1 accent colour for the food, no sound. just give me the html file and then 2 sentences on how to change speed + grid size"

[ -d "$SOURCE" ] || { echo "No Debug build at $SOURCE — run scripts/build.sh first" >&2; exit 1; }
mkdir -p "$OUT"

# A tiny window lister: id, layer, on screen, area and title of every window of one process.
LISTER="$OUT/.list-windows"
if [ ! -x "$LISTER" ]; then
  cat >"$LISTER.swift" <<'SWIFT'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let area = Int((bounds["Width"] ?? 0) * (bounds["Height"] ?? 0))
    let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) == true ? 1 : 0
    print(window[kCGWindowNumber as String] as? Int ?? 0, window[kCGWindowLayer as String] as? Int ?? 0,
          onScreen, area, window[kCGWindowName as String] as? String ?? "", separator: "\t")
}
SWIFT
  xcrun swiftc -O "$LISTER.swift" -o "$LISTER"
  rm -f "$LISTER.swift"
fi

cleanup() {
  pkill -f "^$APP/Contents/MacOS/Afino" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "^$APP/Contents/MacOS/Afino" >/dev/null || break; sleep 0.3; done
  rm -rf "$APP"
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$DOMAIN.plist"
}
trap cleanup EXIT

rm -rf "$APP"
ditto "$SOURCE" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOMAIN" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null

# The copy starts as an installed, set-up app: no welcome, nothing of 0.x to clean up, ⌃⌥P as its
# shortcut (as the welcome shows it), Settings on the Engine pane.
defaults write "$DOMAIN" onboardingCompleted -bool true
defaults write "$DOMAIN" legacyCleanupDone -bool true
defaults write "$DOMAIN" activationShortcut -data "$(printf '{"internalModifiers":786432,"keyCode":35}' | xxd -p | tr -d '\n')"
defaults write "$DOMAIN" settingsSelectedPane engine

# shoot <window layer> <scene>=<seconds after launch> … -- <launch arguments>
# Launches the copy once and captures its largest window on that layer (3: the panel, with any
# menu it shows; 0: an ordinary window) at each time given.
shoot() {
  local layer="$1"; shift
  local shots=()
  while [ "$1" != "--" ]; do shots+=("$1"); shift; done
  shift
  local start pid line id onscreen scene at
  start=$(date +%s)
  open -n "$APP" --args --in-memory-secrets -AppleLanguages "(en)" "$@"
  for shot in "${shots[@]}"; do
    scene="${shot%%=*}"; at="${shot#*=}"
    while [ $(( $(date +%s) - start )) -lt "$at" ]; do sleep 0.2; done
    pid=$(pgrep -f "^$APP/Contents/MacOS/Afino" | head -1 || true)
    [ -n "$pid" ] || { echo "  $scene: the app is not running" >&2; return 1; }
    line=$("$LISTER" "$pid" | awk -F'\t' -v layer="$layer" '$2 == layer && $4 > 20000' | sort -t$'\t' -k4 -n -r | head -1)
    id=$(cut -f1 <<<"$line"); onscreen=$(cut -f3 <<<"$line")
    if [ -z "$id" ] || [ "$onscreen" != 1 ]; then
      echo "  $scene: the window was not on screen (focus moved?) — take it again" >&2
      continue
    fi
    # -o: no shadow (render-doc-images.swift draws its own); -l: this window and its child windows.
    screencapture -x -o -l "$id" "$OUT/$scene.png"
    echo "  $scene.png"
  done
  pkill -f "^$APP/Contents/MacOS/Afino" 2>/dev/null || true
  sleep 1
}

want() { [ ${#SCENES[@]} -eq 0 ] || [[ " ${SCENES[*]} " == *" $1 "* ]]; }
SCENES=("$@")

echo "Capturing into $OUT"
if want result; then
  shoot 3 result=13 -- --demo-engine --demo-open --demo-draft "$DRAFT" --demo-submit
fi
if want target-menu; then
  shoot 3 target-menu=4 -- --demo-engine --demo-open --demo-draft "$DRAFT" --demo-menu target
fi
if want refine; then
  shoot 3 refine=18 -- --demo-engine --demo-open --demo-draft "$DRAFT" --demo-submit --demo-refine Shorter
fi
if want history; then
  shoot 3 history=4 -- --demo-engine --demo-open --demo-history
fi
if want settings-engine; then
  shoot 0 settings-engine=5 -- --open-settings
fi
