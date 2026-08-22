#!/usr/bin/env bash
# Positive control for the flureadium_lints analyzer plugin.
#
# `dart analyze --fatal-infos` exits 0 both when the rules ran and found nothing
# and when they never loaded at all, so a clean analyze proves nothing on its
# own. Three measured ways the rules stop running while analysis stays green are
# in flureadium/docs/05-testing/lint-rules.md: a `diagnostics:` map that drifts
# out of its plugin key, a nested package whose deeper `plugins:` section wins,
# and a package root with no section of its own.
#
# So: drop a known-vacuous assertion into each analyzed package, require both
# diagnostics, and delete it again. A package that reports neither has lost its
# wiring, whatever its own analyze run says.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# Package directory (relative to the repo root) -> probe path inside it. Each
# probe must live where that package's own `plugins:` block applies, which is
# why example gets its own rather than relying on the flureadium/ run.
PACKAGES=(
	"flureadium_platform_interface:test/flureadium_lints_probe_test.dart"
	"flureadium:test/flureadium_lints_probe_test.dart"
	"flureadium/example:test/flureadium_lints_probe_test.dart"
)

PROBE_SOURCE="// Temporary probe written by flureadium/scripts/check_lint_wiring.sh.
// It is deleted when the script exits. If you are reading this in a diff,
// the script died before cleanup — delete the file.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flureadium_lints wiring probe', () {
    const probe = 'probe';
    expect(probe, isNotNull);
    expect(probe, isA<String>());
  });
}
"

probe_files=()
cleanup() {
	if [ ${#probe_files[@]} -gt 0 ]; then
		rm -f "${probe_files[@]}"
	fi
}
trap cleanup EXIT

exit_code=0

for entry in "${PACKAGES[@]}"; do
	package_dir="${entry%%:*}"
	probe_rel="${entry#*:}"
	probe_path="$REPO_ROOT/$package_dir/$probe_rel"

	if [ -e "$probe_path" ]; then
		echo "FAIL $package_dir — $probe_rel already exists; refusing to overwrite it"
		exit_code=1
		continue
	fi

	printf '%s' "$PROBE_SOURCE" >"$probe_path"
	probe_files+=("$probe_path")

	# No path argument, deliberately: `dart analyze <path>` ignores
	# `analyzer: exclude`, so a path-based probe would pass while the row it
	# guards — plain `dart analyze --fatal-infos` — walked an excluded tree and
	# checked nothing. Run what the gate runs.
	output=$(cd "$REPO_ROOT/$package_dir" && dart analyze 2>&1)

	missing=()
	for code in vacuous_not_null_assertion vacuous_type_assertion; do
		case "$output" in
		*"$code"*) ;;
		*) missing+=("$code") ;;
		esac
	done

	rm -f "$probe_path"

	if [ ${#missing[@]} -eq 0 ]; then
		echo "PASS $package_dir — both rules reported on the probe"
	else
		echo "FAIL $package_dir — plugin reported nothing for: ${missing[*]}"
		echo "     the rules are not wired up here. Check the plugins: block and the"
		echo "     analyzer: exclude list in $package_dir/analysis_options.yaml —"
		echo "     see flureadium/docs/05-testing/lint-rules.md"
		echo "$output" | sed 's/^/     /'
		exit_code=1
	fi
done

if [ "$exit_code" -eq 0 ]; then
	echo "flureadium_lints is wired up in all ${#PACKAGES[@]} packages"
fi

exit "$exit_code"
