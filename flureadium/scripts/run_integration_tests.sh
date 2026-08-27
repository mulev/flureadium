#!/bin/bash

# Integration Test Runner for Flureadium
#
# Runs integration tests for Android, iOS, and Web sequentially.
# Continues on test failure — reports a summary at the end.
#
# Usage:
#   ./scripts/run_integration_tests.sh [options]
#
# Options:
#   --android-device <id>   Android device/emulator ID (prompted if omitted)
#   --ios-device <id>       iOS device/simulator ID (prompted if omitted)
#   --skip-android          Skip Android tests
#   --skip-ios              Skip iOS tests
#   --skip-web              Skip Web tests
#   --verbose               Show full flutter output (printed after each test)
#   --help                  Show this help and exit
#
# Web prerequisites:
#   ChromeDriver is required for web tests. The script will attempt to start it
#   automatically (using the system `chromedriver` binary or `npx chromedriver`).
#   If auto-start fails you will be prompted with manual instructions.
#
# Android note:
#   Runs everything, tags included. CI runs the same aggregator with
#   --exclude-tags "native || network", because GitHub-hosted emulators have
#   no audio or TTS engine and no route to the public internet. A local run
#   has both, so it is the only place the tagged tests execute — treat a green
#   CI run as silent about them.
#   Native logcat is captured to android_native.log alongside flutter output
#   to diagnose hangs and native-side issues that don't surface in Dart logs.
#   Before the Android leg the script pins Google TTS as the default engine
#   (secure setting tts_default_synth). A cold-booted or wiped emulator has no
#   default synthesizer, so the EPUB TTS tests query an unconfigured engine,
#   get an empty voice list, and fail nondeterministically.
#   It also checks that the device can reach readium.org by name, and refuses to
#   run the Android leg when it cannot: a dead resolver fails every
#   network-tagged test at once, which reads like a plugin defect. That is a
#   forced skip like any other — iOS and Web still run and the run fails at the
#   end naming Android. Launch the emulator with -dns-server 8.8.8.8,8.8.4.4.
#
# Tags:
#   native  — needs a real audio or TTS engine
#   network — needs the public internet
#   Applied to tests, not as library-level @Tags: an annotation is ignored once
#   an aggregator imports the file rather than running it, and an aggregator is
#   what every path here runs.
#
# iOS note:
#   Runs everything too, including the audio suites. Requires a connected
#   device or booted simulator (iOS >= 16).
#   Native reader diagnostics are captured to ios_native.log, the way logcat is
#   on Android. That capture goes through `simctl`, which only knows simulators,
#   so a run against a physical device leaves the file unwritten and warns; the
#   leg still runs.
#
# Skips, and which ones are allowed:
#   A suite skipped because you asked for it (--skip-android, --skip-ios,
#   --skip-web, or answering "skip web" at the prompt) is a choice, and the run
#   still exits 0. A suite skipped for any other reason — no device found, no
#   ChromeDriver on an unattended run — did not execute what was asked of it, so
#   the run exits non-zero and says which suite never ran. A green run therefore
#   means every requested suite actually executed; it never means "nothing was
#   available to run".

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
LOG_BASE="$PLUGIN_DIR/test_logs"
ADB="$(command -v adb 2>/dev/null || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")"

# ── Defaults ──────────────────────────────────────────────────────────────────
VERBOSE=false
SKIP_ANDROID=false
SKIP_IOS=false
SKIP_WEB=false
ANDROID_DEVICE=""
IOS_DEVICE=""
SELECTED_DEVICE=""      # written by select_device()
CHROMEDRIVER_PID=""     # set when this script starts ChromeDriver
LOGCAT_PID=""          # set when capturing Android native logs
IOS_LOG_PID=""          # set when capturing iOS native logs
IOS_SIM_UDID=""         # simulator the iOS native log stream attaches to
ALL_DEVICES_STRIPPED="" # set once by the device scan; reused by both select_device calls

# ── Argument parsing ──────────────────────────────────────────────────────────
# Prints the header comment block above: everything from line 3 down to the
# blank line that ends it. Reading to the delimiter rather than to a hard-coded
# last line matters — the range used to be '3,38p', which stopped on the bare
# "Tags:" heading and dropped the two tag descriptions under it. A header that
# grows silently truncates --help when the number has to be moved by hand.
usage() {
  sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --android-device) ANDROID_DEVICE="$2"; shift 2 ;;
    --ios-device)     IOS_DEVICE="$2";     shift 2 ;;
    --skip-android)   SKIP_ANDROID=true;   shift ;;
    --skip-ios)       SKIP_IOS=true;       shift ;;
    --skip-web)       SKIP_WEB=true;       shift ;;
    --verbose)        VERBOSE=true;        shift ;;
    --help|-h)        usage ;;
    *)
      printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Log directory ─────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$LOG_BASE/run_$TIMESTAMP"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/summary.log"

# ── Process cleanup ───────────────────────────────────────────────────────────
# Kill stale chromedriver/Chrome from previous interrupted runs.
pkill -f chromedriver 2>/dev/null || true

# Stops a background process this script started. No-op on an empty PID, so
# callers can pass a capture that never started. Callers clear their own PID
# variable afterwards, so cleanup() does not kill it a second time.
stop_process() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  stop_process "$LOGCAT_PID"
  stop_process "$IOS_LOG_PID"
  if [ -n "$CHROMEDRIVER_PID" ]; then
    # Kill Chrome instances spawned by ChromeDriver (child processes) first,
    # then kill ChromeDriver itself. Without this, Chrome stays orphaned.
    pkill -P "$CHROMEDRIVER_PID" 2>/dev/null || true
    stop_process "$CHROMEDRIVER_PID"
  fi
}
trap cleanup EXIT
trap 'exit 2' INT TERM

# ── Logging helpers ───────────────────────────────────────────────────────────
log() {
  echo -e "$1" | tee -a "$SUMMARY_LOG"
}

# True only when a human can answer a prompt. `/dev/tty` exists and is
# world-readable even with no controlling terminal, so `[ -r /dev/tty ]` lies —
# probe by opening it. Without this, every `read </dev/tty` below fails instantly
# and its retry loop spins, flooding the log (measured: 2 GiB in 24 minutes).
# Redirect stderr first: bash applies redirections left to right, so opening
# `/dev/tty` before `2> /dev/null` leaks a "Device not configured" line.
has_tty() { : 2> /dev/null < /dev/tty; }

# ── Device selection ──────────────────────────────────────────────────────────
# Filters ALL_DEVICES_STRIPPED by <pattern>, auto-selects if only one match,
# prompts if multiple. Sets SELECTED_DEVICE; returns 1 if none found.
select_device() {
  local label="$1"
  local pattern="$2"
  SELECTED_DEVICE=""

  local -a lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" | grep -q '(wireless)' && continue
    if echo "$line" | grep -qE "$pattern"; then
      lines+=("$line")
    fi
  done <<< "$ALL_DEVICES_STRIPPED"

  if [[ ${#lines[@]} -eq 0 ]]; then
    log "  ${RED}No $label device or emulator/simulator found.${NC}"
    log "  Connect a device or start an emulator/simulator, then re-run."
    return 1
  fi

  if [[ ${#lines[@]} -eq 1 ]]; then
    log "  $label: ${lines[0]}"
    SELECTED_DEVICE=$(echo "${lines[0]}" | awk -F' • ' '{print $2}' | xargs)
    return 0
  fi

  log "  Multiple $label devices found:"
  local i
  for i in "${!lines[@]}"; do
    log "    $((i+1))) ${lines[$i]}"
  done

  local choice=1
  if has_tty; then
    while true; do
      printf "\n  Select $label device [1-%d]: " "${#lines[@]}" >&2
      read -r choice </dev/tty || { choice=1; break; }
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#lines[@]} )); then
        break
      fi
      printf "  Enter a number between 1 and %d.\n" "${#lines[@]}" >&2
    done
  else
    log "  No terminal to ask on — taking the first $label device."
  fi

  local selected="${lines[$((choice-1))]}"
  SELECTED_DEVICE=$(echo "$selected" | awk -F' • ' '{print $2}' | xargs)
}

# simctl only knows simulator UDIDs. `flutter devices` prints exactly that for a
# simulator, so the direct hit is the common case; the Booted fallback covers a
# device string that is not a bare UDID. A physical device resolves to nothing,
# and streaming a different device's log would be worse than streaming none.
resolve_ios_sim_udid() {
  IOS_SIM_UDID=""
  local listing booted
  listing=$(xcrun simctl list devices 2>/dev/null) || return 1

  if [ -n "$IOS_DEVICE" ] && echo "$listing" | grep -qF "($IOS_DEVICE)"; then
    IOS_SIM_UDID="$IOS_DEVICE"
    return 0
  fi

  booted=$(echo "$listing" | grep '(Booted)' \
    | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}')
  # `grep -c .` counts non-empty lines, so this is "exactly one booted
  # simulator". With none there is nothing to stream; with several there is no
  # way to tell which one the tests will land on.
  if [ "$(echo "$booted" | grep -c .)" -eq 1 ]; then
    IOS_SIM_UDID="$booted"
    return 0
  fi
  return 1
}

# ── Test runner ───────────────────────────────────────────────────────────────
# --verbose: streams all output live to the terminal via tee.
# default:   uses --reporter expanded for clean per-test output; native logs
#            are filtered out. Full output is always in the log file.
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
    cat "$logfile" >> "$SUMMARY_LOG"
  else
    "$@" 2>&1 | tee "$logfile" | grep --line-buffered -v -E \
      '^\[\[|^ReaderStatus:|^onPageChanged:|^creationParams='
    exit_code=${PIPESTATUS[0]}
  fi

  if [ $exit_code -eq 0 ]; then
    log "${GREEN}   passed${NC}"
    return 0
  else
    log "${RED}   FAILED${NC}"
    if [ "$VERBOSE" = false ]; then
      log "   Output (${logfile}):"
      grep -v -E '^\[\[|^ReaderStatus:|^onPageChanged:|^creationParams=' "$logfile" | tee -a "$SUMMARY_LOG"
    fi
    return 1
  fi
}

# ── Android TTS setup ─────────────────────────────────────────────────────────
# The EPUB TTS integration tests query the system TTS engine for voices. On a
# cold-booted or wiped emulator the default synthesizer is unset
# (tts_default_synth == null), so TextToSpeech init returns an empty voice list
# and the TTS tests fail nondeterministically. Pin Google TTS as the default so
# the engine is configured before the suite runs. Best-effort: never aborts the
# run, only warns when it can't.
ensure_android_tts() {
  local device="$1"
  local engine="com.google.android.tts"

  if ! "$ADB" -s "$device" shell pm list packages 2>/dev/null | grep -q "$engine"; then
    log "  ${YELLOW}TTS: $engine not installed on $device — TTS tests may report no voices.${NC}"
    return 0
  fi

  local current
  current=$("$ADB" -s "$device" shell settings get secure tts_default_synth 2>/dev/null | tr -d '\r')
  if [ "$current" = "$engine" ]; then
    log "  TTS: default engine already set ($engine)."
    return 0
  fi

  "$ADB" -s "$device" shell settings put secure tts_default_synth "$engine" 2>/dev/null || true
  local after
  after=$("$ADB" -s "$device" shell settings get secure tts_default_synth 2>/dev/null | tr -d '\r')
  if [ "$after" = "$engine" ]; then
    log "  TTS: default engine set to $engine (was '${current:-null}')."
  else
    log "  ${YELLOW}TTS: could not set default engine (got '${after:-null}').${NC}"
  fi
}

# ── Android DNS pre-flight ────────────────────────────────────────────────────
# The network-tagged tests fetch https://readium.org/webpub-manifest/examples/
# MobyDick/manifest.json from the device. An emulator that inherited a dead
# resolver from the host fails every one of them, which reads exactly like a
# plugin defect — that is how a 100% WebPub open failure was filed as a code
# bug. So probe the capability those tests need and nothing else: resolve the
# manifest host by name, complete a TCP handshake to it.
#
# Not ping. The virtual router forwards all outbound TCP and UDP but "might not
# support other protocols, such as ICMP, which is used for 'ping'"
# (developer.android.com/studio/run/emulator-networking-address), so a failed
# ping is the documented normal state of a healthy emulator.
#
# Unlike ensure_android_tts, this is not best-effort: it returns non-zero and
# the caller marks the Android leg NOT RUN, which fails the run at the end. A
# probe that could not run is a failure, not a pass — a runner that skips its
# work and exits 0 is a lie no ledger can catch. It stops the Android leg only:
# the iOS and Web legs still run, and the summary still names what did not.
ensure_android_dns() {
  local device="$1"
  local host="readium.org"
  local port=443

  # Both "device unreachable" and "no nc on the image" land here, because a
  # failed `adb -s` is indistinguishable from a failed remote command. Name both
  # rather than assert the wrong one at someone who mistyped a device id.
  if ! "$ADB" -s "$device" shell 'command -v nc' > /dev/null 2>&1; then
    log "  ${RED}DNS: the name-resolution pre-flight could not run on $device.${NC}"
    log "  Either the device is unreachable (check the id against 'adb devices'), or its image has no 'nc'."
    log "  The check is not optional. Use a standard system image (toybox provides nc), or pass --skip-android."
    return 1
  fi

  if "$ADB" -s "$device" shell "nc -w 5 $host $port < /dev/null" > /dev/null 2>&1; then
    log "  DNS: $device resolved $host and connected on $port."
    return 0
  fi

  log "  ${RED}DNS: $device cannot reach $host:$port by name — every network-tagged test would fail.${NC}"
  log "  The emulator copies the host's resolver list at startup, so an IPv6-first host list can leave it"
  log "  with a server it has no route to. Give the AVD its own resolver (the AVD directory name can differ"
  log "  from the AVD name — Medium_Phone_API_33 lives in Medium_Phone_2.avd):"
  log "    echo 'commandLineOptions=-dns-server 8.8.8.8,8.8.4.4' >> ~/.android/avd/<avd-dir>.avd/user-settings.ini"
  log "  or launch it with: emulator -avd <name> -dns-server 8.8.8.8,8.8.4.4"
  log "  Then confirm: adb -s $device shell dumpsys connectivity | grep -o 'DnsAddresses: \[[^]]*\]'"
  return 1
}

# ── ChromeDriver helpers ──────────────────────────────────────────────────────

# Returns the Chrome major version number, or empty string if Chrome not found.
detect_chrome_major() {
  local ver=""
  if [[ "$(uname)" == "Darwin" ]]; then
    ver=$("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version 2>/dev/null || true)
  fi
  if [ -z "$ver" ]; then
    ver=$(google-chrome --version 2>/dev/null || \
          chromium-browser --version 2>/dev/null || \
          chromium --version 2>/dev/null || true)
  fi
  echo "$ver" | grep -oE '[0-9]+' | head -1
}

# Polls port 4444 until ChromeDriver responds or <timeout> seconds elapse.
wait_for_chromedriver() {
  local timeout="$1"
  local elapsed=0
  while (( elapsed < timeout )); do
    if curl -s --max-time 1 http://localhost:4444/status > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
    (( elapsed++ )) || true
  done
  return 1
}

# Tries to start ChromeDriver in the background. Sets CHROMEDRIVER_PID on success.
# Returns 0 if ChromeDriver is ready, 1 if all attempts failed.
# When chrome_major is known, npx chromedriver@<major> is tried first to guarantee
# version alignment. The system binary is a fallback for when npx is unavailable.
try_start_chromedriver() {
  local chrome_major="$1"

  log "${YELLOW}Attempting to start ChromeDriver automatically...${NC}"

  # 1. npx chromedriver@<major> — version-matched, preferred when Chrome is detected
  if command -v npx > /dev/null 2>&1 && [ -n "$chrome_major" ]; then
    log "  Trying: npx chromedriver@${chrome_major} --port=4444"
    npx "chromedriver@${chrome_major}" --port=4444 > "$LOG_DIR/chromedriver.log" 2>&1 &
    CHROMEDRIVER_PID=$!
    if wait_for_chromedriver 15; then
      log "${GREEN}  ChromeDriver started via npx (PID $CHROMEDRIVER_PID).${NC}"
      return 0
    fi
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
    CHROMEDRIVER_PID=""
  fi

  # 2. System chromedriver binary — fallback when npx is unavailable or Chrome undetected
  if command -v chromedriver > /dev/null 2>&1; then
    log "  Trying system chromedriver..."
    chromedriver --port=4444 > "$LOG_DIR/chromedriver.log" 2>&1 &
    CHROMEDRIVER_PID=$!
    if wait_for_chromedriver 5; then
      log "${GREEN}  ChromeDriver started (system binary, PID $CHROMEDRIVER_PID).${NC}"
      return 0
    fi
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
    CHROMEDRIVER_PID=""
  fi

  return 1
}

# ── Resolve devices ───────────────────────────────────────────────────────────
ANDROID_SKIP_REASON=""
ANDROID_SKIP_FIX=""
IOS_SKIP_REASON=""
WEB_SKIP_REASON=""

NEEDS_SCAN=false
{ [ "$SKIP_ANDROID" = false ] && [ -z "$ANDROID_DEVICE" ]; } && NEEDS_SCAN=true
{ [ "$SKIP_IOS" = false ]     && [ -z "$IOS_DEVICE" ]; }     && NEEDS_SCAN=true

if [ "$NEEDS_SCAN" = true ]; then
  log ""
  log "${YELLOW}Scanning available devices...${NC}"
  local_raw=$(flutter devices 2>/dev/null || true)
  ALL_DEVICES_STRIPPED=$(echo "$local_raw" | sed 's/\x1b\[[0-9;]*[mK]//g')
fi

if [ "$SKIP_ANDROID" = false ] && [ -z "$ANDROID_DEVICE" ]; then
  if ! select_device "Android" "android"; then
    SKIP_ANDROID=true
    ANDROID_SKIP_REASON="no device found"
  else
    ANDROID_DEVICE="$SELECTED_DEVICE"
  fi
fi

if [ "$SKIP_IOS" = false ] && [ -z "$IOS_DEVICE" ]; then
  if ! select_device "iOS" "(• ios |[Ii][Pp]hone|[Ii][Pp]ad)"; then
    SKIP_IOS=true
    IOS_SKIP_REASON="no device found"
  else
    IOS_DEVICE="$SELECTED_DEVICE"
  fi
fi

# ── Ensure ChromeDriver is available for web ──────────────────────────────────
if [ "$SKIP_WEB" = false ]; then
  if ! curl -s --max-time 2 http://localhost:4444/status > /dev/null 2>&1; then
    log ""
    CHROME_MAJOR=$(detect_chrome_major)
    if ! try_start_chromedriver "$CHROME_MAJOR"; then
      log ""
      log "${YELLOW}ChromeDriver could not be started automatically.${NC}"
      log "Start it manually in a separate terminal, then re-run this script:"
      if [ -n "$CHROME_MAJOR" ]; then
        log "  npx chromedriver@${CHROME_MAJOR} --port=4444"
      else
        log "  npx chromedriver@<your-chrome-major-version> --port=4444"
        log "  (Chrome not found on this machine; install Chrome or Chromium first)"
      fi
      log "Alternatively, check $LOG_DIR/chromedriver.log for the error."
      if has_tty; then
        printf "\nSkip web tests and continue? [Y/n]: " >&2
        read -r skip_web_answer </dev/tty || skip_web_answer=""
        if [[ "$skip_web_answer" =~ ^[Nn]$ ]]; then
          log "Aborted."
          exit 1
        fi
        # A human chose to skip, so this run is still allowed to pass.
      else
        log "No terminal to ask on — the web suite cannot run."
        WEB_SKIP_REASON="ChromeDriver unavailable"
      fi
      SKIP_WEB=true
    fi
  fi
fi

# ── Header ────────────────────────────────────────────────────────────────────
log ""
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "${YELLOW}  Flureadium Integration Test Runner${NC}"
log "${YELLOW}══════════════════════════════════════════════════════════════════${NC}"
log "Plugin:  $PLUGIN_DIR"
log "Logs:    $LOG_DIR"
[ -n "$ANDROID_DEVICE" ] && log "Android: $ANDROID_DEVICE"
[ -n "$IOS_DEVICE" ]     && log "iOS:     $IOS_DEVICE"
log ""

cd "$EXAMPLE_DIR"
OVERALL_EXIT=0

# Build flutter flags once — spliced into every flutter command below.
FLUTTER_VERBOSE=()
FLUTTER_REPORTER=()
if [ "$VERBOSE" = true ]; then
  FLUTTER_VERBOSE=(--verbose)
else
  FLUTTER_REPORTER=(--reporter expanded)
fi

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

# Reports a suite that did not run. A skip the caller asked for is a choice and
# leaves the exit code alone; a skip forced by the environment means the run did
# not do what was asked, so it fails and names the suite. Silence here is how a
# whole platform's suite went unrun while the run reported success.
report_skip() {
  local label="$1" reason="$2" fix="$3"
  if [ -z "$reason" ]; then
    log "  Skipped (explicitly skipped)"
    return
  fi
  log "  ${RED}NOT RUN — $reason.${NC} $label was requested, so this run fails."
  [ -n "$fix" ] && log "  $fix"
  OVERALL_EXIT=1
}

# ── Android ───────────────────────────────────────────────────────────────────
log "${CYAN}── Android ──────────────────────────────────────────────────────────${NC}"
if [ "$SKIP_ANDROID" = false ]; then
  # A dead resolver on the device fails every network-tagged test in a way that
  # looks like a code defect. Refuse to start rather than produce that red.
  # Checked first: it is the cheapest fatal prerequisite, so nothing is
  # installed and no logcat capture is running when it trips.
  #
  # It fails the leg, not the process. Aborting here would drop the iOS and Web
  # legs and the summary along with it, which is the coverage-deleting move this
  # whole check exists to argue against — and it would report a broken resolver
  # by printing nothing about the two suites that never ran.
  if ! ensure_android_dns "$ANDROID_DEVICE"; then
    SKIP_ANDROID=true
    ANDROID_SKIP_REASON="$ANDROID_DEVICE failed the name-resolution pre-flight"
    ANDROID_SKIP_FIX="Give the AVD its own resolver (see the DNS block above), then re-run — or pass --skip-android to run without it."
  fi
fi

if [ "$SKIP_ANDROID" = false ]; then

  # Pin the default TTS engine so the EPUB TTS tests have a configured
  # synthesizer (a cold/wiped emulator leaves it unset → empty voice list).
  ensure_android_tts "$ANDROID_DEVICE"

  # Capture native logcat alongside flutter output so we can diagnose hangs.
  # Clear the buffer first so only this run's output is captured.
  "$ADB" -s "$ANDROID_DEVICE" logcat -c 2>/dev/null || true
  "$ADB" -s "$ANDROID_DEVICE" logcat -v threadtime \
    > "$LOG_DIR/android_native.log" 2>&1 &
  LOGCAT_PID=$!

  if ! run_test \
      "Android — flutter test integration_test/all_tests.dart" \
      "$LOG_DIR/android.log" \
      flutter_test_locked integration_test/all_tests.dart \
        -d "$ANDROID_DEVICE" "${FLUTTER_VERBOSE[@]}" "${FLUTTER_REPORTER[@]}"; then
    OVERALL_EXIT=1
  fi

  stop_process "$LOGCAT_PID"
  LOGCAT_PID=""
  log "  Native logs: $LOG_DIR/android_native.log"
else
  report_skip "Android" "$ANDROID_SKIP_REASON" \
    "${ANDROID_SKIP_FIX:-Start an emulator or attach a device, then re-run — or pass --skip-android to run without it.}"
fi

# ── iOS ───────────────────────────────────────────────────────────────────────
log ""
log "${CYAN}── iOS ──────────────────────────────────────────────────────────────${NC}"
if [ "$SKIP_IOS" = false ]; then
  # Capture the reader's own diagnostics alongside flutter's stdout, the way the
  # Android leg captures logcat. Swift print() reaches neither flutter's stream
  # nor the unified log, which is why ios.log has never carried a native line.
  if resolve_ios_sim_udid; then
    xcrun simctl spawn "$IOS_SIM_UDID" log stream \
      --level debug --style compact \
      --predicate 'subsystem == "dev.mulev.flureadium"' \
      > "$LOG_DIR/ios_native.log" 2>&1 &
    IOS_LOG_PID=$!
  else
    log "  ${YELLOW}No simulator to stream native logs from — ios_native.log will not be written.${NC}"
  fi

  if ! run_test \
      "iOS — flutter test integration_test/all_tests.dart (includes @native audiobook)" \
      "$LOG_DIR/ios.log" \
      flutter_test_locked integration_test/all_tests.dart \
        -d "$IOS_DEVICE" "${FLUTTER_VERBOSE[@]}" "${FLUTTER_REPORTER[@]}"; then
    OVERALL_EXIT=1
  fi

  if [ -n "$IOS_LOG_PID" ]; then
    stop_process "$IOS_LOG_PID"
    IOS_LOG_PID=""
    log "  Native logs: $LOG_DIR/ios_native.log"
  fi
else
  report_skip "iOS" "$IOS_SKIP_REASON" \
    "Boot a simulator (open -a Simulator) or attach a device, then re-run — or pass --skip-ios to run without it."
fi

# ── Web ───────────────────────────────────────────────────────────────────────
log ""
log "${CYAN}── Web ──────────────────────────────────────────────────────────────${NC}"
if [ "$SKIP_WEB" = false ]; then
  if ! run_test \
      "Web — flutter drive --profile (launch smoke test only)" \
      "$LOG_DIR/web.log" \
      flutter drive \
        --driver=test_driver/integration_test.dart \
        --target=integration_test/all_tests_web.dart \
        -d web-server \
        --browser-name=chrome \
        --profile "${FLUTTER_VERBOSE[@]}"; then
    OVERALL_EXIT=1
  fi
else
  report_skip "Web" "$WEB_SKIP_REASON" \
    "Start ChromeDriver on port 4444, then re-run — or pass --skip-web to run without it."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
if [ $OVERALL_EXIT -eq 0 ]; then
  log "${GREEN}All requested suites ran and passed.${NC}"
else
  log "${RED}One or more suites failed or did not run.${NC}"
  log "Logs: $LOG_DIR/"
  if [ "$VERBOSE" = false ]; then
    log "Re-run with --verbose to see full flutter output inline."
  fi
fi
log "${CYAN}══════════════════════════════════════════════════════════════════${NC}"

exit $OVERALL_EXIT
