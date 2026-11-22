#!/bin/bash
# Runs the unit tests of the Swift package (pure logic only: no network, no Keychain, no windows)
# and prints a one-line result, or the failures. Extra arguments go to `swift test`, e.g.
#   scripts/test.sh --filter RunReducerTests
# Needs the Swift toolchain of Xcode 27.2 or later. The live tests and prompt-eval, which spend API
# credit, only run when asked for (CONTRIBUTING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
for package in Packages/PromptImproverKit; do
  log="$(mktemp)"
  if swift test --package-path "$package" "$@" >"$log" 2>&1; then
    grep -E "Test run with" "$log" | sed -E "s/^[^T]*/  /" || true
    echo "TESTS OK ($package)"
  else
    grep -E "error: |✘|failed|Fatal" "$log" | sed -E 's/\x1b\[[0-9;]*m//g' | cut -c1-300 | head -40 || true
    echo "TESTS FAILED ($package) — full log: $log"
    status=1
  fi
done
exit $status
