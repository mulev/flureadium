#!/usr/bin/env bash
#
# Hermetic contract test for scripts/run_integration_tests.sh.
#
# Needs no device, emulator, simulator, or network: stub `flutter`, `adb`,
# `xcrun`, `curl` and `pkill` binaries are prepended to PATH and both device ids
# are passed explicitly, so the runner's device scan never runs. Real `git`
# stays on PATH because resolve_deps asks it whether pubspec.lock is tracked —
# that question is what this test is about.
#
# Usage: ./scripts/run_integration_tests_test.sh   (about 20s, nothing attached)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$SCRIPT_DIR/run_integration_tests.sh"

failures=0

ok()  { echo "ok - $1"; }
bad() { echo "FAIL - $1"; failures=$((failures + 1)); }

check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected '$2', got '$3'"; fi
}

WORK="$(mktemp -d)"
export STUB_LOG="$WORK/calls.log"
: > "$STUB_LOG"
mkdir -p "$WORK/bin"
OUT="$WORK/out.log"

# Log dirs the runner creates under test_logs/ go out with the temp tree.
# An array, not a space-joined string: a log path may contain spaces, and this
# list is the argument to `rm -rf`.
CREATED_LOG_DIRS=()
cleanup_test() {
  rm -rf "$WORK"
  # The `+` guard keeps `set -u` quiet on an empty array under bash 3.2, which
  # is what /bin/bash is on macOS.
  for d in ${CREATED_LOG_DIRS+"${CREATED_LOG_DIRS[@]}"}; do rm -rf "$d"; done
}
trap cleanup_test EXIT

# `flutter`: answers `devices` from a fixed two-row fixture, and otherwise
# records full argv with a millisecond stamp, prints one line on stdout so the
# runner's streaming path has something to carry, sleeps 1s so intervals are
# measurable on this same log, and exits 0 — unless STUB_FAIL_DEVICE names the
# device this invocation targets via -d.
#
# The `devices` case is handled first and returns before the log/sleep/exit
# path: the scan is not a test invocation, so it must not land in $STUB_LOG or
# cost a second. The rows are in real `flutter devices` shape and satisfy three
# consumers in the runner — select_device splits on ' • ' and takes field 2 as
# the id, its Android arm greps `android` and its iOS arm greps
# `(• ios |[Ii][Pp]hone|[Ii][Pp]ad)`, and Phase 4's warn_if_both_virtual greps
# for `(emulator)` and `(simulator)`.
#
# A `test` or `drive` invocation without `--no-pub` records a second line: real
# flutter resolves dependencies implicitly on those subcommands, and that
# implicit resolution is the third writer to .dart_tool/package_config.json the
# pub-get-count assertion exists to catch. Without it the count could only ever
# see the two explicit `pub get` calls, and the Web leg's missing `--no-pub`
# would go unguarded.
cat > "$WORK/bin/flutter" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "devices" ]; then
  echo "sdk gphone64 x86 64 • emulator-5554 • android-x64 • Android 14 (API 34) (emulator)"
  echo "iPhone 16 Pro • IOS1 • ios • com.apple.CoreSimulator.SimRuntime.iOS-18-0 (simulator)"
  exit 0
fi
ts=$(perl -MTime::HiRes=time -e 'printf "%d", time() * 1000')
printf '%s %s\n' "$ts" "$*" >> "$STUB_LOG"
case "${1:-}" in
  test|drive)
    case " $* " in
      *" --no-pub "*) ;;
      *) printf '%s pub get (implicit, %s)\n' "$ts" "$1" >> "$STUB_LOG" ;;
    esac
    ;;
esac
echo "stub flutter: $*"
if [ -n "${STUB_FAIL_DEVICE:-}" ]; then
  prev=""
  for arg in "$@"; do
    if [ "$prev" = "-d" ] && [ "$arg" = "$STUB_FAIL_DEVICE" ]; then
      sleep 1
      exit 1
    fi
    prev="$arg"
  done
fi
sleep 1
exit 0
STUB

# `adb`: device state without a device. STUB_NO_NC=1 makes the
# `adb -s <id> shell 'command -v nc'` probe fail, so ensure_android_dns returns
# 1 and the Android leg is force-skipped — the environment-forced skip A4 needs.
cat > "$WORK/bin/adb" <<'STUB'
#!/bin/bash
if [ "${STUB_NO_NC:-}" = "1" ]; then
  case "$*" in *"command -v nc"*) exit 1 ;; esac
fi
exit 0
STUB

# `xcrun`: covers `simctl list devices` in resolve_ios_sim_udid and the
# `simctl spawn <udid> log stream` capture the iOS leg starts.
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/xcrun"

# `curl`: the runner probes http://localhost:4444/status before the header.
# Exiting 0 makes ChromeDriver look live, so the Web leg proceeds and no npx
# download is attempted.
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/curl"

# `pkill`: the real one runs unconditionally near the top of the runner
# (`pkill -f chromedriver`) and inside cleanup, and would kill the developer's
# own ChromeDriver session mid-test.
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/pkill"

chmod +x "$WORK/bin"/*

# Runs the runner with stub binaries and explicit device ids. $1.. = extra args.
# Sets RUNNER_RC and LAST_LOG_DIR, and remembers the log dir the run created.
run_runner() {
  : > "$STUB_LOG"
  ( cd "$PLUGIN_DIR" && PATH="$WORK/bin:$PATH" "$TARGET" \
      --android-device AND1 --ios-device IOS1 "$@" ) > "$OUT" 2>&1
  RUNNER_RC=$?
  # Strip ANSI first, then take the remainder of the line — never field 2.
  # `awk '{print $2}'` truncates at the first space, so a checkout under
  # `/Users/John Doe/...` yielded `/Users/John`, which the EXIT trap `rm -rf`'d.
  LAST_LOG_DIR=$(sed 's/\x1b\[[0-9;]*[mK]//g' "$OUT" \
    | sed -n 's|^Logs: *\(/.*[^/]\)/*$|\1|p' | sed -n 1p)
  # Belt and braces: only ever delete inside the runner's own test_logs tree, so
  # a future parsing slip cannot reach anything else.
  case "$LAST_LOG_DIR" in
    "$PLUGIN_DIR"/test_logs/*) CREATED_LOG_DIRS+=("$LAST_LOG_DIR") ;;
  esac
}

pub_get_count() { grep -c 'pub get' "$STUB_LOG"; }

line_of() { grep -n "$1" "$OUT" | sed -n 1p | cut -d: -f1; }

if [ ! -x "$TARGET" ]; then
  bad "$TARGET is missing or not executable"
  echo "$failures test(s) failed"
  exit 1
fi

# ── A1. All three stub legs pass → exit 0 ─────────────────────────────────────
run_runner
check "a run with all three stub legs passing exits 0" 0 "$RUNNER_RC"

# ── A2. Dependencies resolve exactly once per run ─────────────────────────────
# RED before step 1.3: Android and iOS each call flutter_test_locked and the Web
# leg's `flutter drive` defaults to --pub, so the count is 3.
check "dependencies resolve exactly once per run" 1 "$(pub_get_count)"

# ── A3. A failing Android leg neither masks nor short-circuits iOS ────────────
# `export`, not a `VAR=x run_runner` prefix: the stub is a separate process and
# would never see a non-exported variable, and bash keeps a prefix assignment on
# a *function* call in effect after the call returns — which would leak the
# failure into A4.
export STUB_FAIL_DEVICE=AND1
run_runner
check "a failing Android leg exits 1" 1 "$RUNNER_RC"
grep -q 'test .*-d IOS1' "$STUB_LOG" \
  && ok "iOS still ran after the Android failure" \
  || bad "iOS never ran after the Android failure"
grep -q 'drive .*all_tests_web.dart' "$STUB_LOG" \
  && ok "Web still ran after the Android failure" \
  || bad "Web never ran after the Android failure"
# Positional, because no single string proves attribution here. `grep -q Android`
# matches the runner's own `Android: AND1` header, and `grep -q 'Android —
# flutter test'` matches the label run_test logs on every invocation, pass or
# fail. The bare FAILED verdict is attributed only by falling inside Android's
# section. Point STUB_FAIL_DEVICE at IOS1 and this assertion must fail.
AND_LINE=$(line_of 'Android — flutter test')
IOS_LINE=$(line_of 'iOS — flutter test')
FAILED_LINE=$(line_of 'FAILED')
if [ -n "$AND_LINE" ] && [ -n "$IOS_LINE" ] && [ -n "$FAILED_LINE" ] \
   && [ "$FAILED_LINE" -gt "$AND_LINE" ] && [ "$FAILED_LINE" -lt "$IOS_LINE" ]; then
  ok "the FAILED verdict falls inside Android's section"
else
  bad "the FAILED verdict is not inside Android's section — failure misattributed"
fi
unset STUB_FAIL_DEVICE

# ── A4. An environment-forced skip fails the run and names the leg ────────────
export STUB_NO_NC=1
run_runner
check "a forced Android skip exits 1" 1 "$RUNNER_RC"
grep -q 'NOT RUN' "$OUT" && ok "the forced skip is reported as NOT RUN" \
  || bad "the forced skip is not reported as NOT RUN"
grep -q 'Android was requested' "$OUT" && ok "the forced skip names Android" \
  || bad "the forced skip does not name Android"
grep -q 'test .*-d IOS1' "$STUB_LOG" \
  && ok "iOS still ran after the forced Android skip" \
  || bad "iOS never ran after the forced Android skip"
grep -q 'drive .*all_tests_web.dart' "$STUB_LOG" \
  && ok "Web still ran after the forced Android skip" \
  || bad "Web never ran after the forced Android skip"
unset STUB_NO_NC

# ── A5. The Web leg ran, against its own target ───────────────────────────────
run_runner
grep -q 'drive .*--target=integration_test/all_tests_web.dart' "$STUB_LOG" \
  && ok "the Web leg ran against all_tests_web.dart" \
  || bad "the Web leg did not run against all_tests_web.dart"

# ── A6. The summary names all three legs in Android → iOS → Web order ─────────
A6_AND=$(line_of '── Android ─')
A6_IOS=$(line_of '── iOS ─')
A6_WEB=$(line_of '── Web ─')
if [ -n "$A6_AND" ] && [ -n "$A6_IOS" ] && [ -n "$A6_WEB" ] \
   && [ "$A6_AND" -lt "$A6_IOS" ] && [ "$A6_IOS" -lt "$A6_WEB" ]; then
  ok "the legs are reported in Android → iOS → Web order"
else
  bad "the legs are not reported in Android → iOS → Web order"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
