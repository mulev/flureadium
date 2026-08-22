#!/bin/bash

# God-Tier Test Runner for Flureadium
#
# Runs every Flureadium test suite in one shot and prints one consolidated
# summary:
#   1. Unit / widget tests  — flutter test / dart test in each Dart package
#                             (plugin, platform interface, example, lints)
#   2. Native unit tests    — scripts/run_native_unit_tests.sh
#                             (Android Kotlin/Robolectric JVM + iOS Swift/XCTest)
#   3. Integration tests    — scripts/run_integration_tests.sh
#                             (full example-app flows on Android + iOS + Web)
#
# Suites run fastest-first (unit -> native -> integration) and, by default,
# every suite runs even if an earlier one fails; the final table shows each
# suite's status, duration, and log file. The exit code is non-zero if any
# suite that ran failed.
#
# Usage:
#   ./scripts/run_all_tests.sh [options]
#
# Suite selection:
#   --skip-unit             Skip the Dart unit/widget tests
#   --skip-native           Skip the native (Android + iOS) unit tests
#   --skip-integration      Skip the integration tests
#   --unit-only             Run only the unit/widget tests
#   --native-only           Run only the native unit tests
#   --integration-only      Run only the integration tests
#
# Platform selection (forwarded to the native and/or integration runners):
#   --skip-android          Skip every Android suite
#   --skip-ios              Skip every iOS suite
#   --skip-web              Skip the Web integration suite (integration only)
#   --android-device <id>   Android device/emulator id (integration)
#   --ios-device <id>       iOS simulator udid (native + integration)
#   --ios-class <Class>     Run only one XCTest class (native iOS)
#
# Behaviour:
#   --fail-fast             Stop after the first failing suite
#   --no-rerun              Reuse Android's Gradle build cache for the native
#                           tests (default: clean rebuild + fresh re-run)
#   --verbose               Stream full tool output for every suite
#   --help, -h              Show this help and exit
#
# Examples:
#   ./scripts/run_all_tests.sh                  # everything
#   ./scripts/run_all_tests.sh --skip-ios       # skip iOS native + iOS integration
#   ./scripts/run_all_tests.sh --unit-only      # just the Dart unit/widget suites
#   ./scripts/run_all_tests.sh --skip-web --skip-native
#   ./scripts/run_all_tests.sh --fail-fast --verbose

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Terminal-only noise filter for the raw Dart unit suites: drops the
# plugin's own reader/page bracket prints so the live view keeps test progress
# and failures. Full output always lands in the log file. The native/integration
# runners already filter their own output.
NOISE_RE='^(\[\[|ReaderStatus:|onPageChanged:|creationParams=)'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/.." && pwd)"
PLATFORM_INTERFACE_DIR="$REPO_ROOT/flureadium_platform_interface"
EXAMPLE_DIR="$PLUGIN_DIR/example"
LINTS_DIR="$REPO_ROOT/flureadium_lints"
LOG_BASE="$PLUGIN_DIR/test_logs/all_tests"
NATIVE_RUNNER="$SCRIPT_DIR/run_native_unit_tests.sh"
INTEGRATION_RUNNER="$SCRIPT_DIR/run_integration_tests.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
SKIP_UNIT=false
SKIP_NATIVE=false
SKIP_INTEGRATION=false
SKIP_ANDROID=false
SKIP_IOS=false
SKIP_WEB=false
ANDROID_DEVICE=""
IOS_DEVICE=""
IOS_CLASS=""
FAIL_FAST=false
RERUN=true
VERBOSE=false

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  sed -n '3,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-unit)        SKIP_UNIT=true;         shift ;;
    --skip-native)      SKIP_NATIVE=true;       shift ;;
    --skip-integration) SKIP_INTEGRATION=true;  shift ;;
    --unit-only)        SKIP_NATIVE=true; SKIP_INTEGRATION=true; shift ;;
    --native-only)      SKIP_UNIT=true; SKIP_INTEGRATION=true;   shift ;;
    --integration-only) SKIP_UNIT=true; SKIP_NATIVE=true;        shift ;;
    --skip-android)     SKIP_ANDROID=true;      shift ;;
    --skip-ios)         SKIP_IOS=true;          shift ;;
    --skip-web)         SKIP_WEB=true;          shift ;;
    --android-device)   ANDROID_DEVICE="$2";    shift 2 ;;
    --ios-device)       IOS_DEVICE="$2";        shift 2 ;;
    --ios-class)        IOS_CLASS="$2";         shift 2 ;;
    --fail-fast)        FAIL_FAST=true;         shift ;;
    --no-rerun)         RERUN=false;            shift ;;
    --verbose)          VERBOSE=true;           shift ;;
    --help|-h)          usage ;;
    *)
      printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Process cleanup ───────────────────────────────────────────────────────────
# Kill any flutter_tester zombies left by an interrupted run; they make
# `flutter devices` hang and hold onto ports.
cleanup() {
  pkill -f flutter_tester 2>/dev/null || true
  pkill -f "flutter_tools.snapshot test" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 2' INT TERM

# ── Log directory ─────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$LOG_BASE/run_$TIMESTAMP"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/summary.log"

log() {
  echo -e "$1" | tee -a "$SUMMARY_LOG"
}

# Formats a whole-second count as "Xm Ys" (or "Ys" under a minute).
fmt_dur() {
  local s=$1
  if [ "$s" -ge 60 ]; then
    echo "$((s / 60))m $((s % 60))s"
  else
    echo "${s}s"
  fi
}

# ── Results (bash 3.2-safe: one "label|status|seconds|logfile" row per suite) ──
RESULTS=()
OVERALL_EXIT=0
STOP=false   # set true once a suite fails under --fail-fast

record() { RESULTS+=("$1|$2|$3|$4"); }

# Runs `flutter test` without any implicit `pub get` that could rewrite a
# committed pubspec.lock. If the lock is version-controlled, resolve strictly to
# it (fail loud on drift — never silently downgrade, e.g. under a wrong SDK).
# If the lock is gitignored (library packages), do NOT run `pub get`: it can
# cascade to sibling packages (a plugin's example) and rewrite THEIR tracked
# locks — require deps already resolved and fail loud otherwise. Then run with
# --no-pub so nothing can mutate any lock. Args are forwarded to `flutter test`.
flutter_test_locked() {
  if git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1; then
    flutter pub get --enforce-lockfile || return $?
  elif [ ! -f .dart_tool/package_config.json ]; then
    echo "flutter_test_locked: dependencies not resolved in $(pwd) — resolve them the usual way for this project, then review and commit any lock changes intentionally (resolving can also update sibling package locks)" >&2
    return 1
  fi
  flutter test --no-pub "$@"
}

# Runs the locked unit/widget suite inside a package directory. Passed to
# run_suite as the command so each package is timed and recorded on its own row.
# $1 = package directory
pkg_flutter_test() {
  ( cd "$1" && flutter_test_locked )
}

# Runs a pure Dart package's locked test suite inside a package directory —
# flureadium_lints, which has no Flutter dependency. Its pubspec.lock is
# version-controlled, so resolve strictly to it with --enforce-lockfile: drift
# fails the row loudly instead of silently rewriting the lock under a different
# SDK. Then `dart test`, never `flutter test`: the analyzer rule harness pulls
# test_reflective_loader, which imports dart:mirrors, and the Flutter test
# runtime rejects that import — worse, it then retries the load forever instead
# of exiting, so a wrong wiring hangs this runner rather than reporting red.
# Passed to run_suite as the command so the package is timed and recorded on its
# own row.
# $1 = package directory
pkg_dart_test() {
  ( cd "$1" && dart pub get --enforce-lockfile && dart test )
}

# Runs a suite command, tees full output to its log, times it, and records the
# result. In non-verbose mode a caller may pass a regex to strip terminal noise
# from the live view; the log file always keeps the full, unfiltered output.
# $1 = label, $2 = logfile, $3 = noise-filter regex (empty = none), $4.. = command
run_suite() {
  local label="$1" logfile="$2" filter="$3"
  shift 3

  log ""
  log "${YELLOW}━━━━━━━━━━ ${label} ━━━━━━━━━━${NC}"
  log "${CYAN}\$ $*${NC}"

  local start code
  start=$(date +%s)
  if [ "$VERBOSE" = false ] && [ -n "$filter" ]; then
    "$@" 2>&1 | tee "$logfile" | grep --line-buffered -v -E "$filter"
    code=${PIPESTATUS[0]}
  else
    "$@" 2>&1 | tee "$logfile"
    code=${PIPESTATUS[0]}
  fi
  local dur=$(($(date +%s) - start))

  if [ "$code" -eq 0 ]; then
    log "${GREEN}✔ ${label} passed in $(fmt_dur "$dur")${NC}"
    record "$label" PASS "$dur" "$logfile"
  else
    log "${RED}✘ ${label} FAILED (exit ${code}) in $(fmt_dur "$dur")${NC}"
    record "$label" FAIL "$dur" "$logfile"
  fi
  return "$code"
}

# Runs a suite unless it is skipped or fail-fast has already tripped.
# $1 = label, $2 = logfile, $3 = skip flag, $4 = noise filter, $5.. = command
run_or_skip() {
  local label="$1" logfile="$2" skipflag="$3" filter="$4"
  shift 4

  if [ "$skipflag" = true ]; then
    log ""
    log "${BLUE}‣ ${label} — skipped${NC}"
    record "$label" SKIP 0 "(--skip)"
    return
  fi
  if [ "$STOP" = true ]; then
    log ""
    log "${BLUE}‣ ${label} — skipped (fail-fast)${NC}"
    record "$label" SKIP 0 "(fail-fast)"
    return
  fi

  run_suite "$label" "$logfile" "$filter" "$@"
  if [ $? -ne 0 ]; then
    OVERALL_EXIT=1
    [ "$FAIL_FAST" = true ] && STOP=true
  fi
}

# ── Build delegated argument lists ────────────────────────────────────────────
NATIVE_ARGS=()
INTEGRATION_ARGS=()

if [ "$SKIP_ANDROID" = true ]; then
  NATIVE_ARGS+=(--skip-android)
  INTEGRATION_ARGS+=(--skip-android)
fi
if [ "$SKIP_IOS" = true ]; then
  NATIVE_ARGS+=(--skip-ios)
  INTEGRATION_ARGS+=(--skip-ios)
fi
# Web is an integration-only platform; the native runner has no web leg.
[ "$SKIP_WEB" = true ] && INTEGRATION_ARGS+=(--skip-web)
[ -n "$ANDROID_DEVICE" ] && INTEGRATION_ARGS+=(--android-device "$ANDROID_DEVICE")
if [ -n "$IOS_DEVICE" ]; then
  NATIVE_ARGS+=(--ios-device "$IOS_DEVICE")
  INTEGRATION_ARGS+=(--ios-device "$IOS_DEVICE")
fi
[ -n "$IOS_CLASS" ] && NATIVE_ARGS+=(--ios-class "$IOS_CLASS")
[ "$RERUN" = true ] && NATIVE_ARGS+=(--rerun)
if [ "$VERBOSE" = true ]; then
  NATIVE_ARGS+=(--verbose)
  INTEGRATION_ARGS+=(--verbose)
fi

# ── Header ────────────────────────────────────────────────────────────────────
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "${YELLOW}  Flureadium — God-Tier Test Runner (unit + native + integration)${NC}"
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "Plugin:    $PLUGIN_DIR"
log "Logs:      $LOG_DIR"
log "Suites:    unit=$([ "$SKIP_UNIT" = true ] && echo skip || echo run)  native=$([ "$SKIP_NATIVE" = true ] && echo skip || echo run)  integration=$([ "$SKIP_INTEGRATION" = true ] && echo skip || echo run)"
[ "$SKIP_ANDROID" = true ] && log "Android:   skipped"
[ "$SKIP_IOS" = true ]     && log "iOS:       skipped"
[ "$SKIP_WEB" = true ]     && log "Web:       skipped"
[ "$FAIL_FAST" = true ]    && log "Mode:      fail-fast"
[ "$RERUN" = false ]       && log "Native:    Gradle cache reuse (no clean rebuild)"
log ""

WALL_START=$(date +%s)
cd "$PLUGIN_DIR" || exit 1

# Guard: the delegated runners must exist before we claim to run their suites.
if [ "$SKIP_NATIVE" = false ] && [ ! -x "$NATIVE_RUNNER" ]; then
  log "${RED}Native runner not found or not executable: $NATIVE_RUNNER${NC}"
  SKIP_NATIVE=true
  OVERALL_EXIT=1
fi
if [ "$SKIP_INTEGRATION" = false ] && [ ! -x "$INTEGRATION_RUNNER" ]; then
  log "${RED}Integration runner not found or not executable: $INTEGRATION_RUNNER${NC}"
  SKIP_INTEGRATION=true
  OVERALL_EXIT=1
fi

# ── Run suites (fastest first) ────────────────────────────────────────────────
# Unit / widget tests — one row per Dart package so the summary pinpoints which
# package broke. All four share the SKIP_UNIT gate.
run_or_skip "Unit — plugin" "$LOG_DIR/unit_plugin.log" "$SKIP_UNIT" "$NOISE_RE" \
  pkg_flutter_test "$PLUGIN_DIR"

run_or_skip "Unit — platform interface" "$LOG_DIR/unit_platform_interface.log" "$SKIP_UNIT" "$NOISE_RE" \
  pkg_flutter_test "$PLATFORM_INTERFACE_DIR"

run_or_skip "Unit — example" "$LOG_DIR/unit_example.log" "$SKIP_UNIT" "$NOISE_RE" \
  pkg_flutter_test "$EXAMPLE_DIR"

run_or_skip "Unit — lints" "$LOG_DIR/unit_lints.log" "$SKIP_UNIT" "$NOISE_RE" \
  pkg_dart_test "$LINTS_DIR"

run_or_skip "Native unit tests" "$LOG_DIR/native.log" "$SKIP_NATIVE" "" \
  "$NATIVE_RUNNER" "${NATIVE_ARGS[@]}"

run_or_skip "Integration tests" "$LOG_DIR/integration.log" "$SKIP_INTEGRATION" "" \
  "$INTEGRATION_RUNNER" "${INTEGRATION_ARGS[@]}"

# ── Summary ───────────────────────────────────────────────────────────────────
WALL_DUR=$(($(date +%s) - WALL_START))

log ""
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
log "${CYAN}  Summary${NC}"
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
for entry in "${RESULTS[@]}"; do
  IFS='|' read -r lbl st dsec info <<< "$entry"
  case $st in
    PASS) log "  ${GREEN}✔ PASS${NC}  $(printf '%-26s' "$lbl")  $(fmt_dur "$dsec")" ;;
    FAIL) log "  ${RED}✘ FAIL${NC}  $(printf '%-26s' "$lbl")  $(fmt_dur "$dsec")   ${info}" ;;
    SKIP) log "  ${BLUE}‣ SKIP${NC}  $(printf '%-26s' "$lbl")  ${info}" ;;
  esac
done
log ""
log "  Total wall time: $(fmt_dur "$WALL_DUR")"
log "  Logs:            $LOG_DIR/"
if [ "$OVERALL_EXIT" -eq 0 ]; then
  log "${GREEN}  ✅ ALL RUN SUITES PASSED${NC}"
else
  log "${RED}  ❌ ONE OR MORE SUITES FAILED${NC}"
fi
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"

exit $OVERALL_EXIT
