#!/usr/bin/env bash
#
# Fixture-driven tests for ios_suite_load_timed_out.sh.
#
# Every fixture below was captured from a real `flutter test --file-reporter`
# run and then trimmed (stack traces elided, paths shortened). The interesting
# property is which test id carries the error: the suite-load timeout lands on
# the `loading ...` pseudo-test, while a test-body timeout carries the very same
# TimeoutException message on a real test id. Matching the message alone would
# confuse the two.
#
# Usage: ./ios_suite_load_timed_out_test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
predicate="$script_dir/ios_suite_load_timed_out.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# check <name> <expected: retry|no-retry> <fixture file>
check() {
  local name=$1 expected=$2 file=$3 actual

  if "$predicate" "$file" >/dev/null 2>&1; then
    actual=retry
  else
    actual=no-retry
  fi

  if [ "$actual" = "$expected" ]; then
    echo "ok   - $name ($actual)"
  else
    echo "FAIL - $name: expected $expected, got $actual"
    failures=$((failures + 1))
  fi
}

# The signature this fix exists for: the load phase never finished, so the
# timeout fires against the `loading ...` pseudo-test.
cat > "$work/suite_load_timeout.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/all_tests.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/all_tests.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"error":"TimeoutException after 0:10:00.000000: Test timed out after 10 minutes.","stackTrace":"<trimmed>","isFailure":false,"type":"error"}
{"testID":1,"result":"error","type":"testDone"}
{"type":"done"}
EOF

# A broken source file also fails during loading, but deterministically —
# retrying only burns runner minutes.
cat > "$work/compile_failure.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/all_tests.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/all_tests.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"error":"Failed to load \"integration_test/all_tests.dart\":\nCompilation failed for testPath=integration_test/all_tests.dart: Error: Expected ';' after this.","stackTrace":"<trimmed>","isFailure":false,"type":"error"}
{"testID":1,"result":"error","type":"testDone"}
{"type":"done"}
EOF

# A genuine assertion failure: the suite ran, so the job result is real.
cat > "$work/assertion_failure.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/all_tests.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/all_tests.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"result":"success","type":"testDone"}
{"group":{"id":2,"name":""},"type":"group"}
{"test":{"id":3,"name":"opens an epub","suiteID":0,"groupIDs":[2]},"type":"testStart"}
{"testID":3,"error":"Expected: <2>\n  Actual: <1>\n","stackTrace":"<trimmed>","isFailure":true,"type":"error"}
{"testID":3,"result":"failure","type":"testDone"}
{"type":"done"}
EOF

# Same TimeoutException text as the hang, but against a real test — the suite
# started, so this is a product problem and must not be retried.
cat > "$work/test_body_timeout.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/all_tests.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/all_tests.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"result":"success","type":"testDone"}
{"group":{"id":2,"name":""},"type":"group"}
{"test":{"id":3,"name":"plays an audiobook","suiteID":0,"groupIDs":[2]},"type":"testStart"}
{"testID":3,"error":"TimeoutException after 0:00:30.000000: Test timed out after 30 seconds.","stackTrace":"<trimmed>","isFailure":false,"type":"error"}
{"testID":3,"result":"error","type":"testDone"}
{"type":"done"}
EOF

# A clean run still writes an events file; nothing to retry.
cat > "$work/all_passed.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/all_tests.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/all_tests.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"result":"success","type":"testDone"}
{"group":{"id":2,"name":""},"type":"group"}
{"test":{"id":3,"name":"opens an epub","suiteID":0,"groupIDs":[2]},"type":"testStart"}
{"testID":3,"result":"success","type":"testDone"}
{"type":"done"}
EOF

# The iOS step passes one file today, so one suite loads. Guard the case anyway:
# if a second file is ever added and its load is the one that stalls, the check
# must still catch it rather than only inspecting the first suite.
cat > "$work/later_suite_timeout.json" <<'EOF'
{"type":"start"}
{"suite":{"id":0,"platform":"vm","path":"integration_test/epub_test.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading integration_test/epub_test.dart","suiteID":0,"groupIDs":[]},"type":"testStart"}
{"suite":{"id":4,"platform":"vm","path":"integration_test/audiobook_test.dart"},"type":"suite"}
{"test":{"id":5,"name":"loading integration_test/audiobook_test.dart","suiteID":4,"groupIDs":[]},"type":"testStart"}
{"type":"allSuites"}
{"testID":1,"result":"success","type":"testDone"}
{"testID":5,"error":"TimeoutException after 0:10:00.000000: Test timed out after 10 minutes.","stackTrace":"<trimmed>","isFailure":false,"type":"error"}
{"testID":5,"result":"error","type":"testDone"}
{"type":"done"}
EOF

# Degenerate inputs: the tool can die before the reporter flushes anything.
: > "$work/empty.json"
printf '{"type":"start"}\n{"test":{"id":1,"name":"loading integration' > "$work/truncated.json"

check "suite-load timeout is retried"        retry    "$work/suite_load_timeout.json"
check "timeout in a later suite is retried"  retry    "$work/later_suite_timeout.json"
check "compile failure is not retried"       no-retry "$work/compile_failure.json"
check "assertion failure is not retried"     no-retry "$work/assertion_failure.json"
check "test-body timeout is not retried"     no-retry "$work/test_body_timeout.json"
check "passing run is not retried"           no-retry "$work/all_passed.json"
check "empty events file is not retried"     no-retry "$work/empty.json"
check "truncated events file is not retried" no-retry "$work/truncated.json"
check "missing events file is not retried"   no-retry "$work/does_not_exist.json"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi

echo "all tests passed"
