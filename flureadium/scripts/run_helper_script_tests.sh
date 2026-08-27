#!/bin/bash

# Helper-script test runner for Flureadium
#
# Runs the injected page script's own suite, then proves the bundle that
# actually ships to the webview still matches the TypeScript it was built from.
#
#   1. jest             — assets/_helper_scripts/src/*.test.ts (ts-jest + jsdom)
#   2. bundle freshness — npm run build:flutter, then require the rebuilt
#                         assets/helpers/ files to be identical to the
#                         committed ones
#
# Nothing here is optional. A missing node or npm is a FAILURE, not a skip: the
# caller's row promised this suite ran, and a runner that skips its work and
# still exits 0 is a lie the validator ledger cannot catch. Only a skip the
# caller asked for (run_all_tests.sh --skip-helpers) may exit 0.
#
# Usage:
#   ./scripts/run_helper_script_tests.sh
#
# Exit codes:
#   0  jest passed and the committed bundle matches its source
#   1  jest failed, the bundle is stale, or the toolchain is missing

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_SRC_DIR="$PLUGIN_DIR/assets/_helper_scripts"
BUNDLE_DIR="$PLUGIN_DIR/assets/helpers"

fail() {
  printf "${RED}%b${NC}\n" "$1" >&2
  exit 1
}

# Toolchain. Missing tools mean the suite did not run, so the row is red.
for tool in node npm; do
  command -v "$tool" >/dev/null 2>&1 ||
    fail "NOT RUN — '$tool' is not on PATH, so the helper-script suite never executed.\nInstall Node 22 and re-run. This is a failure, not a skip."
done

[ -d "$HELPER_SRC_DIR" ] || fail "Helper-script sources not found: $HELPER_SRC_DIR"
[ -d "$BUNDLE_DIR" ]     || fail "Shipped bundle directory not found: $BUNDLE_DIR"

cd "$HELPER_SRC_DIR" || fail "Cannot enter $HELPER_SRC_DIR"

# Cold tree only: npm ci resolves strictly to the committed package-lock.json.
# A warm tree is left alone so repeated local runs stay fast.
if [ ! -d node_modules ]; then
  printf "${YELLOW}Installing helper-script dependencies (npm ci)...${NC}\n"
  npm ci || fail "npm ci failed in $HELPER_SRC_DIR"
fi

# npx jest, never `npm test`: package.json's test script is `jest --watchAll`,
# which never exits and would hang the caller instead of reporting red.
printf "${YELLOW}---------- helper scripts: jest ----------${NC}\n"
npx jest --ci || fail "Helper-script jest suite failed."

# The freshness check covers the whole helpers directory, not just epub.js.
# build:flutter writes epub.js, epub.css, comics.js and comics.css, and a stale
# comics.js is the same defect: a committed artifact that no longer matches the
# source it claims to come from.
printf "${YELLOW}---------- helper scripts: bundle freshness ----------${NC}\n"
npm run build:flutter || fail "npm run build:flutter failed, so bundle freshness could not be checked."

# `git status --porcelain`, not `git diff`: diff reports tracked modifications
# only, so a build that starts emitting a NEW file into assets/helpers/ would
# leave it untracked and the check would pass — the exact silent drift this
# suite exists to catch. Porcelain reports modified, untracked and deleted alike.
STALE="$(git status --porcelain -- "$BUNDLE_DIR")"
if [ -n "$STALE" ]; then
  git --no-pager diff --stat -- "$BUNDLE_DIR"
  fail "Stale bundle — the shipped files no longer match their TypeScript source:
$STALE
Codes: ' M' modified, '??' new and untracked, ' D' deleted.
The rebuilt files are left in place on purpose: review the diff above and commit
them alongside your source change.
  cd flureadium/assets/_helper_scripts && npm run build:flutter"
fi

printf "${GREEN}OK - helper scripts: jest green, assets/helpers/ matches its source${NC}\n"
