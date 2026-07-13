#!/bin/bash

# Native Unit Test Runner for Flureadium
#
# Runs the platform-native unit tests that live outside `flutter test`:
#   - Android: Kotlin/Robolectric JVM tests (testDebugUnitTest)
#   - iOS:     Swift/XCTest tests (RunnerTests)
#
# Runs both sequentially, continues on failure, and prints a summary.
# It detects the tools each platform needs and, when detection fails,
# asks you for a path instead of giving up — so it works on a fresh
# checkout by another contributor, not just the original machine.
#
# Usage:
#   ./scripts/run_native_unit_tests.sh [options]
#
# Options:
#   --skip-android        Skip Android tests
#   --skip-ios            Skip iOS tests
#   --rerun               Force a complete clean rebuild and fresh re-run of the
#                         Android tests: runs `clean` and passes `--rerun-tasks`,
#                         so every task recompiles from scratch (no up-to-date or
#                         build-cache reuse) and the tests run against a fresh
#                         build. Slower; use when you want a guaranteed real run.
#   --java-home <path>    Use this JDK instead of auto-detecting (Android)
#   --ios-device <id>     iOS simulator UDID to use (auto-detected if omitted)
#   --ios-class <Class>   Run only one XCTest class, e.g. ModelTests
#   --verbose             Stream full tool output to the terminal
#   --help                Show this help and exit
#
# Android notes:
#   Tests run through the example app's Gradle wrapper
#   (example/android/gradlew), so no separate Gradle install is needed.
#   The task is :flureadium:testDebugUnitTest. Robolectric runs on the JVM,
#   so no device or emulator is required — only a JDK 17+.
#   Gradle skips the test task when its inputs are unchanged (reported as
#   UP-TO-DATE), so a no-op re-run executes nothing. Pass --rerun for a full
#   clean rebuild (clean + --rerun-tasks) that always recompiles and runs fresh.
#
# iOS notes (macOS only):
#   The script builds the example app for the simulator first
#   (flutter build ios --simulator --debug) — XCTest fails silently without
#   a fresh build when test files or dependencies changed. It then runs
#   xcodebuild test against a booted simulator, booting one if needed.

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$PLUGIN_DIR/example"
ANDROID_APP_DIR="$EXAMPLE_DIR/android"
IOS_APP_DIR="$EXAMPLE_DIR/ios"
LOG_BASE="$PLUGIN_DIR/test_logs"
MIN_JAVA_MAJOR=17

# ── Defaults ──────────────────────────────────────────────────────────────────
VERBOSE=false
SKIP_ANDROID=false
SKIP_IOS=false
RERUN=false
JAVA_HOME_OVERRIDE=""
IOS_DEVICE=""
IOS_CLASS=""
BOOTED_BY_SCRIPT=""   # simulator UDID this script booted (shut down on exit)

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
  sed -n '3,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-android) SKIP_ANDROID=true; shift ;;
    --skip-ios)     SKIP_IOS=true;     shift ;;
    --rerun)        RERUN=true;        shift ;;
    --java-home)    JAVA_HOME_OVERRIDE="$2"; shift 2 ;;
    --ios-device)   IOS_DEVICE="$2";   shift 2 ;;
    --ios-class)    IOS_CLASS="$2";    shift 2 ;;
    --verbose)      VERBOSE=true;      shift ;;
    --help|-h)      usage ;;
    *)
      printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Log directory ─────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$LOG_BASE/native_run_$TIMESTAMP"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/summary.log"

# ── Logging helper ────────────────────────────────────────────────────────────
log() {
  echo -e "$1" | tee -a "$SUMMARY_LOG"
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
  if [ -n "$BOOTED_BY_SCRIPT" ]; then
    log "  Shutting down simulator booted by this script ($BOOTED_BY_SCRIPT)."
    xcrun simctl shutdown "$BOOTED_BY_SCRIPT" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 2' INT TERM

# ── Test runner ───────────────────────────────────────────────────────────────
# Lines worth surfacing live in non-verbose mode. The full output always lands
# in the per-step log file; this only trims the terminal view. Gradle and
# xcodebuild bury the result under build chatter (UP-TO-DATE tasks, code
# signing, framework copying), so we keep the build/test verdicts and anything
# that looks like a failure, and drop the rest.
SIGNAL_FILTER='BUILD SUCCESSFUL|BUILD FAILED|FAILURE:|Test Case |Test Suite |Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|\*\* TEST|tests? completed|> Task .*FAILED| > .*(PASSED|FAILED|SKIPPED)$|error:|[Ee]xception|AssertionError'

# Streams to a per-platform log. --verbose echoes everything; otherwise only the
# signal lines above are shown live, and the failure tail is dumped on failure.
run_test() {
  local label="$1"
  local logfile="$2"
  shift 2

  log ""
  log "${BLUE}▶  $label${NC}"

  local exit_code=0
  if [ "$VERBOSE" = true ]; then
    "$@" 2>&1 | tee "$logfile"
    exit_code=${PIPESTATUS[0]}
  else
    "$@" 2>&1 | tee "$logfile" | grep --line-buffered -E "$SIGNAL_FILTER"
    exit_code=${PIPESTATUS[0]}
  fi

  if [ $exit_code -eq 0 ]; then
    log "${GREEN}   passed${NC}"
    return 0
  fi
  log "${RED}   FAILED${NC}"
  if [ "$VERBOSE" = false ]; then
    log "   Last 40 lines of ${logfile}:"
    tail -n 40 "$logfile" | tee -a "$SUMMARY_LOG"
  else
    log "   See $logfile"
  fi
  return 1
}

# ── Java detection ────────────────────────────────────────────────────────────
# Echoes the major version of the JDK at $1, or nothing if it can't be read.
java_major_at() {
  local home="$1"
  [ -x "$home/bin/java" ] || return 0
  local raw
  raw=$("$home/bin/java" -version 2>&1 | head -1)
  # Matches `"17.0.9"`, `"1.8.0_xxx"`, `"21"`; collapses old 1.x scheme to x.
  local ver
  ver=$(echo "$raw" | grep -oE '"[0-9._]+"' | tr -d '"')
  case "$ver" in
    1.*) echo "$ver" | cut -d. -f2 ;;
    "")  : ;;
    *)   echo "$ver" | cut -d. -f1 ;;
  esac
}

# Validates a candidate JAVA_HOME against MIN_JAVA_MAJOR. Sets RESOLVED_JAVA_HOME
# and returns 0 on success.
RESOLVED_JAVA_HOME=""
try_java_home() {
  local home="$1"
  [ -n "$home" ] || return 1
  local major
  major=$(java_major_at "$home")
  [ -n "$major" ] || return 1
  if (( major >= MIN_JAVA_MAJOR )); then
    RESOLVED_JAVA_HOME="$home"
    return 0
  fi
  return 1
}

# Detects a usable JDK from common locations; prompts for a path if none works.
detect_java() {
  RESOLVED_JAVA_HOME=""

  # 1. Explicit override or inherited JAVA_HOME.
  try_java_home "$JAVA_HOME_OVERRIDE" && return 0
  try_java_home "$JAVA_HOME" && return 0

  # 2. macOS java_home helper, newest qualifying JDK.
  if command -v /usr/libexec/java_home > /dev/null 2>&1; then
    local mac_home
    mac_home=$(/usr/libexec/java_home -v "${MIN_JAVA_MAJOR}+" 2>/dev/null || true)
    try_java_home "$mac_home" && return 0
  fi

  # 3. JetBrains Runtime shipped with Android Studio (macOS + Linux globs).
  local candidate
  for candidate in \
    /Applications/Android\ Studio*.app/Contents/jbr/Contents/Home \
    "$HOME"/Applications/Android\ Studio*.app/Contents/jbr/Contents/Home \
    /opt/android-studio*/jbr \
    "$HOME"/android-studio*/jbr; do
    try_java_home "$candidate" && return 0
  done

  # 4. java on PATH — resolve to its home.
  if command -v java > /dev/null 2>&1; then
    local bin home
    bin=$(command -v java)
    # Follow symlinks where realpath is available.
    if command -v realpath > /dev/null 2>&1; then
      bin=$(realpath "$bin")
    fi
    home=$(dirname "$(dirname "$bin")")
    try_java_home "$home" && return 0
  fi

  # 5. Ask the user.
  log "${YELLOW}Could not auto-detect a JDK ${MIN_JAVA_MAJOR}+ for Android tests.${NC}"
  log "Gradle 8.x needs JDK ${MIN_JAVA_MAJOR} or newer."
  while true; do
    printf "\n  Enter the path to a JDK %d+ home (or 'skip' to skip Android): " \
      "$MIN_JAVA_MAJOR" >&2
    local answer
    read -r answer </dev/tty
    if [ "$answer" = "skip" ]; then
      return 1
    fi
    if try_java_home "$answer"; then
      return 0
    fi
    printf "  Not a valid JDK %d+ home: %s\n" "$MIN_JAVA_MAJOR" "$answer" >&2
  done
}

# ── iOS simulator detection ───────────────────────────────────────────────────
# Lists booted simulators; if none, offers to boot one. Sets IOS_DEVICE.
resolve_ios_simulator() {
  [ -n "$IOS_DEVICE" ] && return 0

  local booted
  booted=$(xcrun simctl list devices available 2>/dev/null \
    | grep 'Booted' | grep -oE '[A-F0-9-]{36}' | head -1)
  if [ -n "$booted" ]; then
    IOS_DEVICE="$booted"
    log "  Using booted simulator: $IOS_DEVICE"
    return 0
  fi

  log "  No booted simulator. Available iPhone simulators:"
  local -a names=() ids=()
  while IFS= read -r line; do
    local name id
    name=$(echo "$line" | sed -E 's/ \([A-F0-9-]{36}\).*//' | xargs)
    id=$(echo "$line" | grep -oE '[A-F0-9-]{36}' | head -1)
    [ -z "$id" ] && continue
    names+=("$name"); ids+=("$id")
  done < <(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone')

  if [ ${#ids[@]} -eq 0 ]; then
    log "  ${RED}No iPhone simulators installed.${NC} Create one in Xcode, then re-run."
    return 1
  fi

  local i
  for i in "${!ids[@]}"; do
    log "    $((i+1))) ${names[$i]}  (${ids[$i]})"
  done

  local choice
  while true; do
    printf "\n  Select a simulator to boot [1-%d]: " "${#ids[@]}" >&2
    read -r choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ids[@]} )); then
      break
    fi
    printf "  Enter a number between 1 and %d.\n" "${#ids[@]}" >&2
  done

  IOS_DEVICE="${ids[$((choice-1))]}"
  log "  Booting ${names[$((choice-1))]} ($IOS_DEVICE)..."
  xcrun simctl boot "$IOS_DEVICE" 2>/dev/null || true
  BOOTED_BY_SCRIPT="$IOS_DEVICE"
  # Give the simulator a moment to come up before xcodebuild attaches.
  xcrun simctl bootstatus "$IOS_DEVICE" -b 2>/dev/null || true
  return 0
}

# ── Header ────────────────────────────────────────────────────────────────────
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "${YELLOW}  Flureadium Native Unit Test Runner${NC}"
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "Plugin:  $PLUGIN_DIR"
log "Logs:    $LOG_DIR"
log ""

OVERALL_EXIT=0

# ── Android ───────────────────────────────────────────────────────────────────
log "${CYAN}── Android (Kotlin/Robolectric) ─────────────────────────────────────${NC}"
if [ "$SKIP_ANDROID" = false ]; then
  if [ ! -x "$ANDROID_APP_DIR/gradlew" ]; then
    log "  ${RED}No Gradle wrapper at $ANDROID_APP_DIR/gradlew.${NC}"
    log "  Run 'flutter pub get' in $EXAMPLE_DIR first."
    OVERALL_EXIT=1
  elif ! detect_java; then
    log "  Skipped — no usable JDK ${MIN_JAVA_MAJOR}+."
  else
    log "  JDK:    $RESOLVED_JAVA_HOME"
    log "  Task:   :flureadium:testDebugUnitTest"
    # Default: run only the test task (Gradle reports UP-TO-DATE and executes
    # nothing when the tree is unchanged). --rerun instead does a full clean
    # rebuild: `clean` wipes all build outputs and `--rerun-tasks` ignores every
    # task optimization (up-to-date AND build cache), so everything recompiles
    # and the tests run against a fresh build.
    GRADLE_TASKS=( :flureadium:testDebugUnitTest )
    GRADLE_RERUN_FLAG=()
    if [ "$RERUN" = true ]; then
      GRADLE_TASKS=( clean :flureadium:testDebugUnitTest )
      GRADLE_RERUN_FLAG=( --rerun-tasks )
      log "  Rerun:  forced clean rebuild (clean + --rerun-tasks)"
    fi
    if ! ( cd "$ANDROID_APP_DIR" && JAVA_HOME="$RESOLVED_JAVA_HOME" \
        run_test \
          "Android — :flureadium:testDebugUnitTest" \
          "$LOG_DIR/android.log" \
          ./gradlew "${GRADLE_TASKS[@]}" "${GRADLE_RERUN_FLAG[@]}" --console=plain ); then
      OVERALL_EXIT=1
    fi
  fi
else
  log "  Skipped (explicitly skipped)"
fi

# ── iOS ───────────────────────────────────────────────────────────────────────
log ""
log "${CYAN}── iOS (Swift/XCTest) ───────────────────────────────────────────────${NC}"
if [ "$SKIP_IOS" = false ]; then
  if [ "$(uname)" != "Darwin" ]; then
    log "  Skipped — iOS tests require macOS."
  elif ! command -v xcrun > /dev/null 2>&1; then
    log "  ${RED}xcrun not found.${NC} Install Xcode and command-line tools, then re-run."
    OVERALL_EXIT=1
  elif ! resolve_ios_simulator; then
    log "  Skipped — no simulator available."
  else
    # Mandatory: build before testing, or XCTest fails silently.
    log "  Building example app for the simulator (required before XCTest)..."
    if ! ( cd "$EXAMPLE_DIR" && \
        run_test \
          "iOS — flutter build ios --simulator --debug" \
          "$LOG_DIR/ios_build.log" \
          flutter build ios --simulator --debug ); then
      log "  ${RED}Build failed — skipping iOS tests.${NC}"
      OVERALL_EXIT=1
    else
      ONLY_TESTING="RunnerTests"
      [ -n "$IOS_CLASS" ] && ONLY_TESTING="RunnerTests/$IOS_CLASS"
      if ! ( cd "$IOS_APP_DIR" && \
          run_test \
            "iOS — xcodebuild test ($ONLY_TESTING)" \
            "$LOG_DIR/ios_test.log" \
            xcodebuild test \
              -workspace Runner.xcworkspace \
              -scheme Runner \
              -configuration Debug \
              -destination "id=$IOS_DEVICE" \
              -only-testing:"$ONLY_TESTING" ); then
        OVERALL_EXIT=1
      fi
    fi
  fi
else
  log "  Skipped (explicitly skipped)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
if [ $OVERALL_EXIT -eq 0 ]; then
  log "${GREEN}All native unit tests passed.${NC}"
else
  log "${RED}One or more native unit test runs failed or could not start.${NC}"
  log "Logs: $LOG_DIR/"
fi
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"

exit $OVERALL_EXIT
