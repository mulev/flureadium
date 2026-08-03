#!/usr/bin/env bash
#
# Tests for android_integration_tests.sh.
#
# The bug these guard against: reactivecircus/android-emulator-runner splits its
# `script:` input on newlines and runs every line in a separate `sh -c`
# (src/script-parser.ts, src/main.ts). A multi-line body loses its variables,
# its `set` flags and its line continuations, and a trailing `\` survives as a
# literal argument. That is why the wrapper is a file the action calls once.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/android_integration_tests.sh"
WORKFLOW="$SCRIPT_DIR/../workflows/integration-test.yml"
MARKER="aitest-$$"

failures=0

ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1"; failures=$((failures + 1)); }

check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected '$2', got '$3'"; fi
}

# Build a sandbox with stub `adb` and `flutter` on PATH.
# $1 = exit code for flutter, $2 = seconds the stub logcat runs.
make_sandbox() {
  work="$(mktemp -d)"
  mkdir -p "$work/bin" "$work/temp"
  cat > "$work/bin/adb" <<EOF
#!/usr/bin/env bash
# $MARKER
if [ "\$1" = "logcat" ] && [ "\$2" = "-c" ]; then exit 0; fi
if [ "\$1" = "logcat" ]; then sleep $2; exit 0; fi
exit 0
EOF
  cat > "$work/bin/flutter" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$work/argv.txt"
for a in "\$@"; do
  case "\$a" in json:*) echo '{"type":"done"}' > "\${a#json:}" ;; esac
done
exit $1
EOF
  chmod +x "$work/bin/adb" "$work/bin/flutter"
}

run_target() { # run_target [pipe] -> sets rc, elapsed
  start=$(date +%s)
  if [ "${1:-}" = "pipe" ]; then
    PATH="$work/bin:$PATH" RUNNER_TEMP="$work/temp" "$TARGET" > "$work/out.txt" 2>&1
  else
    PATH="$work/bin:$PATH" RUNNER_TEMP="$work/temp" "$TARGET" > /dev/null 2>&1
  fi
  rc=$?
  elapsed=$(( $(date +%s) - start ))
}

if [ ! -x "$TARGET" ]; then
  bad "$TARGET is missing or not executable"
  echo "$failures test(s) failed"
  exit 1
fi

# 1-2. The suite's exit status is the step's exit status.
make_sandbox 0 1; run_target; check "a passing run exits 0" 0 "$rc"; rm -rf "$work"
make_sandbox 1 1; run_target; check "a failing run exits 1" 1 "$rc"; rm -rf "$work"

# 3-4. Both diagnostics land, on success and on failure.
make_sandbox 1 1; run_target
[ -s "$work/temp/diag/logcat.txt" ] || [ -f "$work/temp/diag/logcat.txt" ] \
  && ok "logcat is captured" || bad "logcat is captured"
[ -f "$work/temp/diag/test-events.json" ] \
  && ok "the event stream is captured" || bad "the event stream is captured"

# 5. Regression for the trailing-backslash bug: flutter must receive exactly
#    three arguments, with no stray continuation character.
expected="test
integration_test/all_tests_android_ci.dart
--file-reporter
json:$work/temp/diag/test-events.json"
check "flutter is invoked with clean arguments" "$expected" "$(cat "$work/argv.txt")"
rm -rf "$work"

# 6. A long-running logcat must not hold the step's stdout open.
make_sandbox 0 15; run_target pipe
if [ "$elapsed" -lt 5 ]; then ok "the log capture does not hold stdout"
else bad "the log capture does not hold stdout: returned after ${elapsed}s"; fi

# 7. The capture process is reaped, not orphaned onto the runner.
sleep 1
if pgrep -f "$MARKER" > /dev/null 2>&1; then bad "the log capture is reaped"
else ok "the log capture is reaped"; fi
rm -rf "$work"

# 8. The workflow must call the wrapper as a single command. A block scalar
#    here is the defect this whole file exists for.
if grep -qE '^[[:space:]]*script:[[:space:]]*[|>]' "$WORKFLOW"; then
  bad "the emulator-runner script input is a single line"
else
  ok "the emulator-runner script input is a single line"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
