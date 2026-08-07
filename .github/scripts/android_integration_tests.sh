#!/usr/bin/env bash
#
# Run the Android integration suite and collect evidence while it runs.
#
# This lives in a file rather than inline in the workflow because
# reactivecircus/android-emulator-runner splits its `script:` input on newlines
# and runs each line in its own `sh -c` (src/script-parser.ts, src/main.ts).
# Variables, `set` flags and line continuations do not survive that, so the
# action gets one command and the shell logic stays here.
#
# The suite dies mid-run in roughly one job in fifteen without leaving anything
# behind. logcat plus the per-test event stream make that readable.

set -u

diag="${RUNNER_TEMP:-/tmp}/diag"
mkdir -p "$diag"

adb logcat -c > /dev/null 2>&1 || true

# Both streams go to the file, so this never holds the step's stdout open and
# cannot stall the runner waiting for EOF.
adb logcat -v threadtime > "$diag/logcat.txt" 2>&1 &
logcat_pid=$!

# Tags, not a second aggregator: what the emulator cannot do is declared by the
# test that needs it. GitHub-hosted emulators have no audio or TTS engine
# (`native`) and no route to the public internet (`network`).
#
# A file left out of an import list is invisible — nothing fails, the tests
# simply never run. That is how the whole audiobook group, including the
# audio-only readiness regression, went unrun here for months
# (flureadium-29l). A tag has to be written on the test, so a new file is
# included by default.
flutter test integration_test/all_tests.dart \
  --exclude-tags "native || network" \
  --file-reporter "json:$diag/test-events.json"
status=$?

# Reap it. Left alone it shows up as an orphan in the runner's cleanup.
kill "$logcat_pid" 2> /dev/null || true
wait "$logcat_pid" 2> /dev/null || true

exit "$status"
