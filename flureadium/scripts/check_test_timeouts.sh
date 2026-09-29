#!/bin/bash

# Wall-clock guard for the native test suites.
#
# A positive wait's timeout is a hang guard, not a sleep: `wait(for:timeout:)`
# returns the moment the expectation is fulfilled, so a wait that takes 2 s
# still costs 2 s under a 60 s ceiling. A per-call literal is therefore never a
# budget — it is a bet that this machine services that callback inside that many
# seconds, and a contended CI runner loses it. It has lost on 2026-09-17,
# 09-19, 09-22 and twice on 09-29.
#
# A RED RUN MEANS: a native test wait hardcoded a number of seconds. Replace it
# with that target's named ceiling — `asyncTimeout` in Swift,
# `latchTimeoutSeconds` in Kotlin. The one legitimate exception is an inverted
# expectation, where the timeout IS the assertion window rather than a deadline;
# mark that line `// inverted: <why>` and the guard allows it.
#
# Not matched, deliberately: Robolectric's `idleFor(...)` and kotlinx's
# `advanceUntilIdle()` advance a virtual clock and assume nothing about the host.
#
# Usage:
#   ./flureadium/scripts/check_test_timeouts.sh      (runs from anywhere)
#
# Exit codes:
#   0  no hardcoded wait literal in the scanned trees
#   1  at least one, or a scanned tree is missing; every offending line is printed

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

fail() {
  printf "${RED}%b${NC}\n" "$1" >&2
}

# tree | file glob | offending pattern
TREES=(
  "flureadium/example/ios/RunnerTests|*.swift|timeout:[[:space:]]*[0-9]"
  "flureadium/example/macos/RunnerTests|*.swift|timeout:[[:space:]]*[0-9]"
  "flureadium/android/src/test|*.kt|\\.await\\([[:space:]]*[0-9]"
)

hits=""
for entry in "${TREES[@]}"; do
  IFS='|' read -r dir glob pattern <<<"$entry"
  if [ ! -d "$REPO_ROOT/$dir" ]; then
    fail "NOT RUN — missing tree: $dir. The guard checked nothing, so this is a failure, not a skip."
    exit 1
  fi
  found=$(grep -rnE "$pattern" --include="$glob" "$REPO_ROOT/$dir" |
    grep -v '// inverted:' |
    sed "s|^$REPO_ROOT/||")
  [ -n "$found" ] && hits+="$found"$'\n'
done

if [ -n "$hits" ]; then
  count=$(printf '%s' "$hits" | wc -l | tr -d ' ')
  fail "$count hardcoded wait literal(s) in the native test suites:"
  printf '%s' "$hits" | sed 's/^/  /' >&2
  fail "Swift: use this target's 'asyncTimeout'. Kotlin: use 'latchTimeoutSeconds'.\nAn inverted expectation keeps its literal and carries '// inverted: <why>'.\nSee flureadium/docs/05-testing/ios-unit-tests.md (Async tests)."
  exit 1
fi

printf "${GREEN}No hardcoded wait literals in the native test suites${NC}\n"
exit 0
