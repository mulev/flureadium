#!/bin/bash

# Wall-clock guard for the test suites, native and Dart.
#
# Native: a positive wait's timeout is a hang guard, not a sleep:
# `wait(for:timeout:)` returns the moment the expectation is fulfilled, so a
# wait that takes 2 s still costs 2 s under a 60 s ceiling. A per-call literal
# is therefore never a budget — it is a bet that this machine services that
# callback inside that many seconds, and a contended CI runner loses it. It has
# lost on 2026-09-17, 09-19, 09-22 and twice on 09-29.
#
# A RED RUN MEANS: a native test wait hardcoded a number of seconds. Replace it
# with that target's named ceiling — `asyncTimeout` in Swift,
# `latchTimeoutSeconds` in Kotlin. The one legitimate exception is an inverted
# expectation, where the timeout IS the assertion window rather than a deadline;
# mark that line `// inverted: <why>` and the guard allows it.
#
# Dart: a test must not wait by sleeping. Stream delivery happens in microtasks,
# so `await pumpEventQueue()` returns exactly when the events have landed, and a
# production Timer is advanced with package:fake_async. `Future.delayed` in a
# test is neither — it is the same bet the native literal is.
#
# A RED RUN MEANS: a Dart test slept. Replace it with `pumpEventQueue()` or with
# `fakeAsync` + `async.elapse(...)`. A case that genuinely exercises elapsed
# time keeps its delay and carries `// real-delay: <why>`.
#
# Not matched, deliberately: Robolectric's `idleFor(...)` and kotlinx's
# `advanceUntilIdle()` advance a virtual clock and assume nothing about the
# host. Production code is not scanned — `orientation_handler_mixin.dart`
# delays by design, and that delay is the behaviour under test. Neither is
# `flureadium/example/integration_test/`, which drives a real app on a real
# device, where waiting is the job.
#
# Usage:
#   ./flureadium/scripts/check_test_timeouts.sh      (runs from anywhere)
#
# Exit codes:
#   0  no clock bet in the scanned trees
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
#
# The patterns are line-oriented, because `grep` is. A label whose argument sits
# on the next line would otherwise be invisible, so each native pattern also
# accepts a dangling label — `timeout:` or `.await(` with nothing after it.
# Zero hits today; the day a formatter wraps one of these calls it stays zero
# by catching it rather than by luck.
NATIVE_TREES=(
  "flureadium/example/ios/RunnerTests|*.swift|timeout:[[:space:]]*([0-9]|$)"
  "flureadium/example/macos/RunnerTests|*.swift|timeout:[[:space:]]*([0-9]|$)"
  "flureadium/android/src/test|*.kt|\\.await\\([[:space:]]*([0-9]|$)"
)

# `Future<void>.delayed(...)` is the same call with the type argument written
# out, and `dart format` leaves both spellings alone, so the pattern has to
# admit one.
DART_TREES=(
  "flureadium/test|*.dart|Future(<[^>]*>)?\\.delayed\\("
  "flureadium_platform_interface/test|*.dart|Future(<[^>]*>)?\\.delayed\\("
  "flureadium/example/test|*.dart|Future(<[^>]*>)?\\.delayed\\("
  "flureadium_lints/test|*.dart|Future(<[^>]*>)?\\.delayed\\("
)

# Scans the given trees and leaves every offending line in HITS. A global rather
# than stdout: a missing tree has to exit the script, and an `exit` inside a
# command substitution only kills the subshell.
#
# The allow marker counts on the matched line or on either neighbour. It has to:
# `dart format` splits a call whose trailing comment pushes it past the column
# limit and carries the comment down to the closing paren, so a marker written
# beside the call does not stay beside it.
HITS=""
scan_trees() { # <allow-marker> <tree entry>...
  local allow="$1"
  shift
  local entry dir glob pattern hit file num from window
  HITS=""
  for entry in "$@"; do
    IFS='|' read -r dir glob pattern <<<"$entry"
    if [ ! -d "$REPO_ROOT/$dir" ]; then
      fail "NOT RUN — missing tree: $dir. The guard checked nothing, so this is a failure, not a skip."
      exit 1
    fi
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      file=${hit%%:*}
      num=${hit#*:}
      num=${num%%:*}
      from=$((num > 1 ? num - 1 : 1))
      # The marker may sit anywhere in the matched statement, or on the line
      # above it. `dart format` splits a call whose trailing comment runs long
      # and moves the comment to the closing paren, which can be two or more
      # lines below the call — so the window runs forward to the statement's
      # `;` rather than a fixed number of lines.
      #
      # The line above counts only when it is not itself an offending call, or
      # an unmarked sleep written directly above a marked one would inherit the
      # marker. Forward lines need no such filter: the scan stops at the `;`
      # that ends this statement, so it cannot reach the next one.
      #
      # Collected first, then matched with a here-string rather than a pipe:
      # under `pipefail`, `grep -q` exits on its first hit and the upstream
      # reader dies with SIGPIPE, which would report the whole pipeline as
      # failed exactly when the marker WAS found.
      window=$(
        sed -n "${from}p" "$file" | grep -vE -- "$pattern"
        awk -v start="$num" 'NR >= start { print; if (/;/) exit }' "$file"
      )
      grep -q -- "$allow" <<<"$window" && continue
      HITS+="${hit#"$REPO_ROOT"/}"$'\n'
    done < <(grep -rnE "$pattern" --include="$glob" "$REPO_ROOT/$dir")
  done
}

report() { # <headline> <advice>
  local count
  count=$(printf '%s' "$HITS" | wc -l | tr -d ' ')
  fail "$count $1"
  printf '%s' "$HITS" | sed 's/^/  /' >&2
  fail "$2"
}

status=0

scan_trees '// inverted:' "${NATIVE_TREES[@]}"
if [ -n "$HITS" ]; then
  report "hardcoded wait literal(s) in the native test suites:" \
    "Swift: use this target's 'asyncTimeout'. Kotlin: use 'latchTimeoutSeconds'.\nAn inverted expectation keeps its literal and carries '// inverted: <why>'.\nSee flureadium/docs/05-testing/ios-unit-tests.md (Async tests)."
  status=1
fi

scan_trees '// real-delay:' "${DART_TREES[@]}"
if [ -n "$HITS" ]; then
  report "test sleep(s) in the Dart test suites:" \
    "Use pumpEventQueue() for stream delivery, fakeAsync + async.elapse(...) for a production Timer.\nA case that genuinely exercises elapsed time keeps its delay and carries '// real-delay: <why>'.\nSee flureadium/docs/05-testing/all-tests.md (Waits must not bet on the clock)."
  status=1
fi

[ "$status" -ne 0 ] && exit 1

printf "${GREEN}No clock bets in the native or Dart test suites${NC}\n"
exit 0
