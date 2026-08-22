#!/usr/bin/env bash
#
# Tests for the JDK pins in .github/workflows/*.yml.
#
# The bug this guards against: JDK 18.0.2 — the only build `setup-java` resolves
# for `java-version: '18'`, since JDK 18 ended at 18.0.2.1 — carries JDK-8287073
# unfixed. Its CgroupSubsystemFactory reads `infos.get("memory")` when the host
# is cgroup v2, and kernels from 6.12 on stopped listing a `memory` row in
# /proc/cgroups. The result is a null controller and a fatal NPE inside AGP's
# JvmWideVariable, which killed :app:validateSigningDebug on every Android job
# after the runner image moved from kernel 6.17.0-1020-azure to -1022.
#
# OpenJDK fixed it in 19 (commit 744b822a picks any available controller) and
# backported to 17.0.5 and 11.0.17, never to 18.x. This repo compiles to
# JvmTarget.JVM_18, so 17 cannot build it either: javac emits no target above
# its own release. That leaves 21 as the floor.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$SCRIPT_DIR/../workflows"
MIN_MAJOR=21

failures=0

ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1"; failures=$((failures + 1)); }

if [ ! -d "$WORKFLOW_DIR" ]; then
  echo "FAIL - no workflow directory at $WORKFLOW_DIR"
  exit 1
fi

# 1. Every pin is at or above the floor. A pin below it either cannot build
#    JvmTarget.JVM_18 (17 and older) or carries the cgroup NPE (18, 19, 20).
pins=0
while IFS= read -r line; do
  file=${line%%:*}
  rest=${line#*:}
  version=$(printf '%s' "$rest" | sed -E "s/.*java-version:[[:space:]]*['\"]?([0-9]+).*/\1/")
  pins=$((pins + 1))
  if [ "$version" -ge "$MIN_MAJOR" ]; then
    ok "$(basename "$file") pins JDK $version"
  else
    bad "$(basename "$file") pins JDK $version, below the JDK $MIN_MAJOR floor"
  fi
done <<EOF
$(grep -rnE "^[[:space:]]*java-version:" "$WORKFLOW_DIR" 2>/dev/null)
EOF

# 2. A workflow that sets up Java at all has to pin a version. `setup-java`
#    fails without one, but a future edit could reach for a default instead,
#    and an unpinned JDK is how the affected one came back.
setups=$(grep -rl "actions/setup-java" "$WORKFLOW_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$pins" -ge "$setups" ]; then
  ok "all $setups workflow(s) using setup-java pin a version"
else
  bad "$setups workflow(s) use setup-java but only $pins pin a version"
fi

# 3. The floor must clear the bytecode target the Gradle builds ask for.
#    Raising jvmTarget without raising this file would pass silently otherwise.
target=$(sed -nE 's/.*JvmTarget\.JVM_([0-9]+).*/\1/p' \
  "$SCRIPT_DIR/../../flureadium/android/build.gradle" | head -1)
if [ -z "$target" ]; then
  bad "could not read JvmTarget from flureadium/android/build.gradle"
elif [ "$MIN_MAJOR" -ge "$target" ]; then
  ok "the JDK $MIN_MAJOR floor covers JvmTarget.JVM_$target"
else
  bad "JvmTarget.JVM_$target needs a JDK floor of at least $target, not $MIN_MAJOR"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all tests passed"
