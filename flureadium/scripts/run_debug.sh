#!/bin/bash

# Debug Runner for the Flureadium example app
#
# Lists attached devices, asks which one to run on, then launches
# `flutter run` on the example app in debug mode. Output is streamed live
# to the terminal AND captured to a timestamped log file in
# test_logs/debug_output/. Hot reload keys (r/R/q) keep working because
# the session runs under macOS `script`, which preserves the TTY.
#
# Use it for the CarPlay STAGE-1 manual gate: run the example on an iOS
# simulator, enable the simulator's CarPlay display, and watch the log
# for the car engine's `[carMain]` round-trip lines.
#
# Usage:
#   ./scripts/run_debug.sh [options]
#
# Options:
#   -d, --device <id>         Skip the prompt and use this device id
#       --initial-asset <p>   Set FLUREADIUM_INITIAL_ASSET (default: bundled Moby Dick)
#       --help                Show this help and exit

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
# The script lives in the plugin's scripts/ dir, but `flutter run` must launch
# the example app, so commands run from EXAMPLE_DIR — the plugin itself is a
# package, not a runnable app.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$PLUGIN_DIR/example"
LOG_DIR="$PLUGIN_DIR/test_logs/debug_output"

if [[ ! -f "$EXAMPLE_DIR/pubspec.yaml" ]]; then
  echo -e "${RED}Example app not found at $EXAMPLE_DIR${NC}" >&2
  echo "Expected a Flutter app there (pubspec.yaml). Is the checkout complete?" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

# ── Args ──────────────────────────────────────────────────────────────────────
DEVICE=""
INITIAL_ASSET=""
usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--device)      DEVICE="$2"; shift 2 ;;
    --initial-asset)  INITIAL_ASSET="$2"; shift 2 ;;
    --help|-h)        usage ;;
    *)
      printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# The example app reads a single optional dart-define; the default bundled asset
# is fine for the CarPlay gate, so this stays empty unless --initial-asset is set.
DART_DEFINES=()
[[ -n "$INITIAL_ASSET" ]] && DART_DEFINES+=("--dart-define=FLUREADIUM_INITIAL_ASSET=$INITIAL_ASSET")

# ── Device selection ──────────────────────────────────────────────────────────
if [[ -z "$DEVICE" ]]; then
  echo -e "${YELLOW}Scanning available devices...${NC}"
  raw=$(flutter devices --device-connection=attached 2>/dev/null || true)
  stripped=$(echo "$raw" | sed 's/\x1b\[[0-9;]*[mK]//g')

  declare -a lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Keep lines shaped like "<name> • <id> • <platform> • <os>"
    echo "$line" | grep -q ' • ' || continue
    echo "$line" | grep -q '(wireless)' && continue
    lines+=("$line")
  done <<< "$stripped"

  if [[ ${#lines[@]} -eq 0 ]]; then
    echo -e "${RED}No devices/emulators/simulators found.${NC}" >&2
    echo "Boot an iOS simulator (open -a Simulator) or connect a device, then re-run." >&2
    exit 1
  fi

  echo "Available devices:"
  for i in "${!lines[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${lines[$i]}"
  done

  while true; do
    printf "\nSelect device [1-%d]: " "${#lines[@]}"
    read -r choice </dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#lines[@]} )); then
      break
    fi
    printf "Enter a number between 1 and %d.\n" "${#lines[@]}"
  done

  selected="${lines[$((choice-1))]}"
  DEVICE=$(echo "$selected" | awk -F' • ' '{print $2}' | xargs)
  echo -e "${GREEN}Selected:${NC} $selected"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/${TIMESTAMP}.log"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Flureadium Example Debug Run${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
echo "Device:  $DEVICE"
echo "Log:     $LOG_FILE"
echo ""

cd "$EXAMPLE_DIR"

# macOS `script` preserves the TTY → hot reload (r/R/q) still works.
# Signature: script [-q] file command [args ...]
exec script -q "$LOG_FILE" flutter run -d "$DEVICE" "${DART_DEFINES[@]}"
