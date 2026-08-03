#!/usr/bin/env bash
#
# Exit 0 when a `flutter test --file-reporter json:...` event stream shows the
# suite-load timeout, i.e. the run died before any test could start.
#
# On an iOS simulator, flutter_tools finds the Dart VM service URL by scraping a
# single os_log line out of `simctl spawn ... log stream`. There is no mDNS or
# fallback path, and the wait is unbounded, so one dropped log record hangs the
# run forever. `suite_load_timeout` in example/dart_test.yaml converts that hang
# into a timeout against the `loading ...` pseudo-test, which is what this
# script looks for so the caller can retry.
#
# The error message alone is not enough to identify it: a test that overruns its
# own timeout reports the identical TimeoutException text. What separates them is
# which test the error belongs to, so match on the load test's id.
#
# Usage: ios_suite_load_timed_out.sh <path to test-events.json>

set -uo pipefail

events=${1:-}

# -s is false for all three degenerate cases: no argument, missing file, empty file.
if [ ! -s "$events" ]; then
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ios_suite_load_timed_out: jq not found; cannot classify the failure" >&2
  exit 1
fi

# A truncated or malformed stream makes jq exit non-zero, which reads as "not
# the hang" — the safe answer, since retrying is the costlier mistake.
jq -e -s '
  [ .[]
    | select(.type == "testStart" and (.test.name // "" | startswith("loading ")))
    | .test.id
  ] as $load_ids
  | ($load_ids | length) > 0
    and any(.[];
        .type == "error"
        and (.testID as $id | $load_ids | index($id)) != null
        and (.error | tostring | test("TimeoutException")))
' "$events" >/dev/null 2>&1
