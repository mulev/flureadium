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
# Usage: ./scripts/run_integration_tests_test.sh   (about 50s, nothing attached)

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
# `simctl spawn <udid> log stream` capture the iOS leg starts. The `list`
# fixture must name the id the harness passes: with no output at all,
# resolve_ios_sim_udid returns 1, the capture branch is never entered, and
# IOS_LOG_PID plus its teardown go untested — the half of the process handling
# the unconditional `adb logcat &` already covers on the Android side.
cat > "$WORK/bin/xcrun" <<'STUB'
#!/bin/bash
case "$*" in
  *"simctl list devices"*)
    echo "    iPhone 16 Flutter Sim (IOS1) (Booted)"
    exit 0
    ;;
  *"log stream"*)
    # The real stream runs until killed, so sleep: that leaves a live
    # grandchild for stop_process to actually stop, while staying short enough
    # that a missed teardown cannot outlast the suite.
    echo "stub xcrun: log stream attached"
    sleep 5
    exit 0
    ;;
esac
exit 0
STUB

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

# ── A7. Each device leg reports its own duration ──────────────────────────────
# Measured from the runner's own output rather than inferred from log mtimes,
# so the parallel saving Phase 4 measures is readable from an archived run.
# Read from the terminal stream, which is what a developer watches during a run,
# and from A5's clean run — the same $OUT A6 reads, so no extra run is needed.
grep -Eq 'Android leg: ([0-9]+m )?[0-9]+s$' "$OUT" \
  && ok "A7 the Android leg logs its own duration" \
  || bad "A7 the Android leg logs no duration"
grep -Eq 'iOS leg: ([0-9]+m )?[0-9]+s$' "$OUT" \
  && ok "A7 the iOS leg logs its own duration" \
  || bad "A7 the iOS leg logs no duration"

# ── A9. --parallel happy path ─────────────────────────────────────────────────
# Red before step 3.4: --parallel does not parse yet, so the runner exits 1 with
# "Unknown option".
run_runner --parallel
check "--parallel with passing stubs exits 0" 0 "$RUNNER_RC"
PAR_DIR="$LAST_LOG_DIR"

# ── A10. exactly one dependency resolution under --parallel ───────────────────
# It cannot double today, because the resolution sits ahead of the dispatch
# branch. It is asserted because moving the call inside the branch is a
# plausible refactor the sequential count would not catch — and that would
# reintroduce the concurrent .dart_tool write the hoist exists to prevent.
check "--parallel resolves dependencies exactly once" 1 "$(pub_get_count)"

# ── A11. each leg's summary holds only its own lines ──────────────────────────
# This is what proves the LOG_TARGET redirection held under concurrency rather
# than both branches falling back to the shared summary.log.
[ -f "$PAR_DIR/android_summary.log" ] \
  && ok "android_summary.log exists" || bad "android_summary.log exists"
[ -f "$PAR_DIR/ios_summary.log" ] \
  && ok "ios_summary.log exists" || bad "ios_summary.log exists"
grep -q 'Android — flutter test' "$PAR_DIR/android_summary.log" \
  && ok "android_summary.log holds Android's own label" \
  || bad "android_summary.log holds Android's own label"
grep -q 'iOS — flutter test' "$PAR_DIR/ios_summary.log" \
  && ok "ios_summary.log holds iOS's own label" \
  || bad "ios_summary.log holds iOS's own label"
if grep -q 'iOS — flutter test' "$PAR_DIR/android_summary.log"; then
  bad "android_summary.log holds iOS label lines"
else ok "android_summary.log holds no iOS label lines"; fi
if grep -q 'Android — flutter test' "$PAR_DIR/ios_summary.log"; then
  bad "ios_summary.log holds Android label lines"
else ok "ios_summary.log holds no Android label lines"; fi
if grep -q '\[ios\]' "$PAR_DIR/android_summary.log"; then
  bad "android_summary.log carries the iOS tag"
else ok "android_summary.log carries no iOS tag"; fi
if grep -q '\[android\]' "$PAR_DIR/ios_summary.log"; then
  bad "ios_summary.log carries the Android tag"
else ok "ios_summary.log carries no Android tag"; fi
# The raw per-suite log must stay unfiltered and untagged: it is the file a
# developer greps for a stack trace, and the tag is added after `tee`.
if grep -q '^\[android\]' "$PAR_DIR/android.log"; then
  bad "android.log was tagged"
else ok "android.log is untagged"; fi
if grep -q '^\[ios\]' "$PAR_DIR/ios.log"; then
  bad "ios.log was tagged"
else ok "ios.log is untagged"; fi

# ── A12a. the streamed terminal output is tagged in default mode ──────────────
# Anchored to the stub's own streamed line, never to log() output: the verdict
# lines carry LOG_TAG too, so a bare '^\[android\] ' matches them and passes
# even with a tagging stage removed. That exact false pass is what fablum's
# adc46388 had to fix.
grep -q '^\[android\] stub flutter:' "$OUT" \
  && ok "--parallel tags streamed Android output" \
  || bad "--parallel tags streamed Android output"
grep -q '^\[ios\] stub flutter:' "$OUT" \
  && ok "--parallel tags streamed iOS output" \
  || bad "--parallel tags streamed iOS output"

# ── A8. the iOS leg starts its native log capture ─────────────────────────────
# Guards the `xcrun` stub's `list` fixture. With no listing at all,
# resolve_ios_sim_udid returns 1, the capture branch is skipped, and
# IOS_LOG_PID plus its `stop_process` teardown silently stop being exercised —
# the half of this runner's process handling that `adb logcat &` covers
# unconditionally on the Android side.
grep -q 'Native logs: .*ios_native.log' "$PAR_DIR/ios_summary.log" \
  && ok "A8 the iOS leg captured native logs" \
  || bad "A8 the iOS leg captured native logs"

# ── A13. the merge assembles summary.log in Android → iOS → Web order ─────────
# A11 reads the per-leg files; this reads the merge they feed. Swapping the
# concatenation's operands, deleting it, or moving it ahead of the waits all
# leave A11 green while the run's summary loses or reorders a leg.
PAR_AND=$(grep -n 'Android — flutter test' "$PAR_DIR/summary.log" | sed -n 1p | cut -d: -f1)
PAR_IOS=$(grep -n 'iOS — flutter test'     "$PAR_DIR/summary.log" | sed -n 1p | cut -d: -f1)
PAR_WEB=$(grep -n 'Web — flutter drive'    "$PAR_DIR/summary.log" | sed -n 1p | cut -d: -f1)
[ -n "$PAR_AND" ] && ok "summary.log holds the Android body" \
  || bad "summary.log holds no Android body after the merge"
[ -n "$PAR_IOS" ] && ok "summary.log holds the iOS body" \
  || bad "summary.log holds no iOS body after the merge"
[ -n "$PAR_WEB" ] && ok "summary.log holds the Web body" \
  || bad "summary.log holds no Web body"
if [ -n "$PAR_AND" ] && [ -n "$PAR_IOS" ] && [ -n "$PAR_WEB" ] \
   && [ "$PAR_AND" -lt "$PAR_IOS" ] && [ "$PAR_IOS" -lt "$PAR_WEB" ]; then
  ok "summary.log is assembled in Android → iOS → Web order"
else
  bad "summary.log order is wrong: android=$PAR_AND ios=$PAR_IOS web=$PAR_WEB"
fi

# ── A12b. --verbose keeps the tag ─────────────────────────────────────────────
# The mode where tagging matters most: --verbose streams both legs' full output,
# and it takes a different branch of run_test. fablum shipped it untagged.
run_runner --parallel --verbose
check "--parallel --verbose exits 0" 0 "$RUNNER_RC"
grep -q '^\[android\] stub flutter:' "$OUT" \
  && ok "--parallel --verbose tags streamed Android output" \
  || bad "--parallel --verbose tags streamed Android output"
grep -q '^\[ios\] stub flutter:' "$OUT" \
  && ok "--parallel --verbose tags streamed iOS output" \
  || bad "--parallel --verbose tags streamed iOS output"

# ── A14. exit-code attribution survives concurrency ───────────────────────────
export STUB_FAIL_DEVICE=AND1
run_runner --parallel
check "--parallel exits 1 when Android fails" 1 "$RUNNER_RC"
grep -q 'Android suite failed' "$OUT" \
  && ok "the summary names Android as the failure" \
  || bad "the summary does not name Android as the failure"
# run_test logs "passed" only after the command exited 0, so this is completion,
# not merely invocation.
grep -q 'passed' "$LAST_LOG_DIR/ios_summary.log" \
  && ok "iOS ran to completion after the Android failure" \
  || bad "iOS did not run to completion after the Android failure"
# A12c. the failure dump is tagged as well. run_test has four output paths and
# this is the only one that runs exclusively on a red leg, so two failing
# parallel legs would otherwise interleave thousands of untagged lines with
# nothing to attribute them to.
#
# Anchored on Android's own stub lines rather than on whatever follows the
# "Output (…):" header: the legs interleave by design, so the line after that
# header is routinely the other leg's, and an adjacency check reports a tagging
# defect that is not there. Android's invocation is echoed twice in a failing
# run, once by the stream and once by the dump, and both must carry the tag —
# so an untagged copy of it anywhere in the terminal output is the dump.
# (Web's lines are legitimately untagged: it runs on the parent, outside the
# fork, with LOG_TAG empty. Hence the `-d AND1` anchor rather than a bare one.)
if grep -q '^stub flutter: .*-d AND1' "$OUT"; then
  bad "A12c the failure dump is untagged"
else
  ok "A12c the failure dump is tagged"
fi
unset STUB_FAIL_DEVICE

# ── A15. the two suites genuinely overlap in time ─────────────────────────────
# THE ONLY assertion that distinguishes real concurrency from an accidentally
# serialized implementation. Every other assertion here passes on a runner that
# calls the two legs one after the other. Each stub invocation sleeps 1s, so its
# interval is at least [ts, ts+1000). If iOS starts less than 1000 ms after
# Android does, Android was still running — the intervals overlap. A serialized
# dispatch cannot produce a gap below 1000 ms, because iOS only starts once
# Android has returned.
run_runner --parallel
check "--parallel overlap run exits 0" 0 "$RUNNER_RC"
stub_start() { awk -v pat="$1" '$0 ~ pat {print $1; exit}' "$STUB_LOG"; }
AND_TS=$(stub_start 'test .*-d AND1')
IOS_TS=$(stub_start 'test .*-d IOS1')
[ -n "$AND_TS" ] && ok "an Android 'flutter test' invocation was recorded" \
  || bad "no Android 'flutter test' invocation recorded"
[ -n "$IOS_TS" ] && ok "an iOS 'flutter test' invocation was recorded" \
  || bad "no iOS 'flutter test' invocation recorded"
if [ -n "$AND_TS" ] && [ -n "$IOS_TS" ]; then
  GAP=$(( AND_TS > IOS_TS ? AND_TS - IOS_TS : IOS_TS - AND_TS ))
  if [ "$GAP" -lt 1000 ]; then
    ok "the two 'flutter test' calls overlap (${GAP}ms apart)"
  else
    bad "suites did not overlap: the two 'flutter test' calls started ${GAP}ms apart, and each runs for at least 1000ms — this is sequential execution"
  fi
fi

# ── A16. the Web leg still runs, after the fork ───────────────────────────────
WEB_TS=$(stub_start 'drive .*-d web-server')
[ -n "$WEB_TS" ] && ok "the Web leg ran under --parallel" \
  || bad "the Web leg did not run under --parallel"
# A15 requires the two device legs to overlap; the Web leg must start after both
# have finished. Every stub `flutter` call sleeps 1s, so a bare `-ge IOS_TS`
# bound is satisfied by a Web leg starting 1ms after iOS — i.e. running
# concurrently with it, which is the regression this guards. ChromeDriver on
# 4444 is a parent-owned singleton with exactly one intended user.
if [ -n "$WEB_TS" ] && [ -n "$IOS_TS" ] && [ "$WEB_TS" -ge "$((IOS_TS + 1000))" ]; then
  ok "the Web leg started after the device legs finished"
else
  bad "the Web leg did not start after the device legs finished: web=$WEB_TS ios=$IOS_TS"
fi

# ── Regression. sequential stays the default and is unchanged ─────────────────
# The sequential path must keep using summary.log alone: no per-leg files, no
# tags in the stream.
run_runner
check "a no-flag run still exits 0" 0 "$RUNNER_RC"
if [ -f "$LAST_LOG_DIR/android_summary.log" ]; then
  bad "a no-flag run wrote android_summary.log"
else ok "a no-flag run writes no per-leg summary file"; fi
if grep -q '^\[android\]' "$OUT"; then
  bad "a no-flag run tagged its stream"
else ok "a no-flag run leaves its stream untagged"; fi

# --parallel needs both legs, so a skipped leg falls back to the sequential path.
run_runner --parallel --skip-ios
check "--parallel --skip-ios exits 0 (a requested skip is a choice)" 0 "$RUNNER_RC"
if [ -f "$LAST_LOG_DIR/android_summary.log" ]; then
  bad "--parallel --skip-ios took the parallel path"
else ok "--parallel --skip-ios falls back to the sequential path"; fi

# ── run_all_tests.sh forwarding ───────────────────────────────────────────────
UMBRELLA="$SCRIPT_DIR/run_all_tests.sh"

# Runs the umbrella with stub binaries and explicit device ids. $1.. = extra
# args. Sets UMBRELLA_RC and INTEGRATION_LOG_DIR — the *integration* runner's
# log dir, which is the last `Logs:` line in this output, not the first: the
# umbrella prints its own first, and the integration row passes an empty noise
# filter so the child's full output is tee'd through.
run_umbrella() {
  : > "$STUB_LOG"
  ( cd "$PLUGIN_DIR" && PATH="$WORK/bin:$PATH" "$UMBRELLA" --integration-only \
      --android-device AND1 --ios-device IOS1 "$@" ) > "$OUT" 2>&1
  UMBRELLA_RC=$?
  local dirs
  dirs=$(sed 's/\x1b\[[0-9;]*[mK]//g' "$OUT" \
    | sed -n 's|^Logs: *\(/.*[^/]\)/*$|\1|p')
  INTEGRATION_LOG_DIR=$(echo "$dirs" | tail -1)
  # Both directories go out with the run: the umbrella writes
  # test_logs/all_tests/run_*, the integration runner test_logs/run_*. The
  # `run_*` anchor keeps `rm -rf` inside a run directory even if the parse slips.
  local d
  while IFS= read -r d; do
    case "$d" in "$PLUGIN_DIR"/test_logs/*run_*) CREATED_LOG_DIRS+=("$d") ;; esac
  done <<< "$dirs"
}

# ── A17. --help prints the whole header block, including --parallel ───────────
# Two checks under one id. A17a is the flag's documentation; A17b is what goes
# red when usage() reads to a hardcoded line number, because every option added
# below the range's end pushes one line off the tail of --help. A17a alone could
# not catch it: the --parallel row sits in the Behaviour block near the top of
# the header and survives a stale range.
help_out="$("$UMBRELLA" --help 2>&1)"
case "$help_out" in
  *--parallel*) ok "A17a --help lists --parallel" ;;
  *) bad "A17a --help lists --parallel" ;;
esac
case "$help_out" in
  *"--fail-fast --verbose"*) ok "A17b --help prints through the last header line" ;;
  *) bad "A17b --help prints through the last header line" ;;
esac

# ── A18. the flag reaches the integration runner ──────────────────────────────
# Behavioural end to end: the only thing asserted about the forwarding is a file
# that exists solely because the integration runner's parallel dispatch created
# it. Asserting on the umbrella's source text would be vacuous.
run_umbrella --parallel
check "A18a the umbrella accepts and forwards --parallel" 0 "$UMBRELLA_RC"
if grep -q 'Unknown option' "$OUT"; then
  bad "A18b --parallel is a known option"
else ok "A18b --parallel is a known option"; fi
if [ -n "$INTEGRATION_LOG_DIR" ] \
   && [ -f "$INTEGRATION_LOG_DIR/android_summary.log" ]; then
  ok "A18c the integration runner ran its parallel dispatch"
else
  bad "A18c the integration runner ran its parallel dispatch"
fi
# The same run covers warn_if_both_virtual's early return: AND1/IOS1 are passed
# explicitly, so no scan runs, neither id is virtual, and no warning may appear.
if grep -q 'both targets are virtual' "$OUT"; then
  bad "A18d two named non-virtual ids print no topology warning"
else ok "A18d two named non-virtual ids print no topology warning"; fi

# ── A19. the topology warning fires when both targets are virtual ─────────────
# This one cannot use run_runner: that helper always passes both device ids, so
# NEEDS_SCAN stays false, ALL_DEVICES_STRIPPED stays empty, and the (simulator)
# grep arm has nothing to read. Omitting --ios-device runs the scan against the
# stub `flutter devices` fixture, which carries one (emulator) row and one
# (simulator) row. No exit-code check: the assertion is about the warning, and
# the stubbed legs' status belongs to A1.
: > "$STUB_LOG"
( cd "$PLUGIN_DIR" && PATH="$WORK/bin:$PATH" "$TARGET" --parallel \
    --android-device emulator-5554 ) > "$OUT" 2>&1
WARN_LOG_DIR=$(sed 's/\x1b\[[0-9;]*[mK]//g' "$OUT" \
  | sed -n 's|^Logs: *\(/.*[^/]\)/*$|\1|p' | sed -n 1p)
case "$WARN_LOG_DIR" in
  "$PLUGIN_DIR"/test_logs/run_*) CREATED_LOG_DIRS+=("$WARN_LOG_DIR") ;;
esac
grep -q 'both targets are virtual' "$OUT" \
  && ok "A19 the topology warning fires on emulator + simulator" \
  || bad "A19 the topology warning fires on emulator + simulator"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
