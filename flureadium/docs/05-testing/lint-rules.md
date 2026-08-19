# Lint Rules

`flureadium_lints/` is a first-party analyzer plugin living at the repo root, next to
`flureadium/` and `flureadium_platform_interface/`. It holds two lint rules that flag
test assertions which cannot fail. Neither published package depends on it: it is a
`publish_to: none` package that the analyzer loads by relative path.

The rules exist because a test whose assertion is always true is worse than no test —
it reports green forever, including after the behaviour it claims to cover breaks.

## The rules

### `vacuous_type_assertion`

Reports `expect(x, isA<T>())` when `x`'s static type is already a subtype of `T`, so
the matcher cannot fail.

```dart
// Reported: the parameter is already a Locator.
void check(Locator locator) {
  expect(locator, isA<Locator>());
}

// Fine: assert what the test actually promises.
void check(Locator locator) {
  expect(locator.href, '/chapter1.xhtml');
}
```

### `vacuous_not_null_assertion`

Reports `expect(x, isNotNull)` when `x`'s static type is non-nullable, so the matcher
cannot fail. Flow analysis counts: a nullable local that an earlier `if (x == null)
return;` promoted to non-null is reported too.

```dart
// Reported: `Locator.href` is a String, never null.
expect(locator.href, isNotNull);

// Fine: assert the value.
expect(locator.href, '/chapter1.xhtml');
```

`Locator.locations` is a `Locations?` and `Locations.progression` a `double?`, so
`expect(locator.locations?.progression, isNotNull)` stays unreported — that one can
genuinely fail.

## What the rules deliberately leave alone

Both rules are pure type questions answered by the analyzer's `TypeSystem`, so they
are exact — and they stay quiet whenever the assertion can genuinely fail:

| Form | Why it is not reported |
|---|---|
| `expect(untyped, isA<List<String>>())` on a `dynamic` target | `dynamic` is not a subtype of `List<String>`; the check can fail |
| `expect(value, isA<int>())` where `value` is `num` | A downcast that can fail at runtime |
| `expect(maybe, isA<Foo>())` where `maybe` is `Foo?` | The null case makes the matcher fallible |
| `expect(() => …, throwsA(isA<FormatException>()))` | The `isA` belongs to `throwsA`, not to `expect` |
| `expect(value, isA<int>().having(…))` | A `having` chain is a value check wearing a type matcher |

`expect(json['metadata'], isNotNull)` is also not reported: a map lookup has static
type `Object?`, so that assertion really can fail.

These two rules cover the first two of the six forms banned by
[Assertions must be able to fail](all-tests.md#assertions-must-be-able-to-fail).
The other four are semantic rather than type-decidable — they depend on what a test's
name promises, or on cross-statement dataflow — and no analyzer rule covers them. They
stay a review concern.

## Running the rule tests

```sh
cd flureadium_lints
dart pub get
dart test
```

**Use `dart test`, never `flutter test`.** The suite uses `test_reflective_loader`,
which imports `dart:mirrors`. The Flutter test runtime rejects that import, and then
retries the load instead of exiting — so `flutter test` here does not fail, it hangs
until something kills it. CI runs this package in its own `test-lints` job for the
same reason.

`dart analyze` in the same directory must print `No issues found!`.

## Suppressing a diagnostic

Plugin diagnostics are namespaced by plugin name:

```dart
// ignore: flureadium_lints/vacuous_type_assertion
expect(locator, isA<Locator>());
```

Use it for a case the rule genuinely gets wrong, and say why in the line above. A
vacuous assertion is a broken test, and the fix is almost always to assert something
that can fail.

## How the analyzer loads the plugin

The analysis server does not use `flureadium_lints/pubspec.lock`. It builds a
synthetic package under `~/.dartServer/.plugin_manager/<hash>`, copies the plugin's
dependency constraints into it, and runs `dart pub upgrade` there. That is why the
plugin cannot conflict with either published package's lockfile — and why the local
lockfile pins only this package's own `dart test` run.

The cost of that independence is SDK lockstep. Dart 3.12.2 pins
`analysis_server_plugin: ^0.3.0`, and `flureadium_lints/pubspec.yaml` matches it. A
future Flutter bump may need that constraint bumped. The failure is loud, not silent:
`dart analyze` exits 4 and prints the pub resolution error. The first analyze run
after a plugin change also pays about 20–25 seconds of bootstrap while that synthetic
package resolves.

Changing a `plugins:` section does not affect an already-running analysis server — it
reads the section once per session. Restart the analysis server after editing one.

## Turning the rules on

Enabling the plugin for a package means one `plugins:` section in its
`analysis_options.yaml`. The key is the plugin's name, and `diagnostics:` is **nested
inside that key** — the rules are lint rules, so they are off until named there:

```yaml
plugins:
  flureadium_lints:
    path: ../flureadium_lints
    diagnostics:
      vacuous_type_assertion: true
      vacuous_not_null_assertion: true
```

Get the nesting wrong and nothing tells you. A top-level `diagnostics:` section, a
sibling of `plugins:` rather than a child of the plugin key, parses cleanly, reports
no diagnostics, and exits 0 — the rules simply never run. Measured on a fixture with
two known violations: the correct shape reported both, the top-level shape reported
`No issues found!`.

## Where the rules are enabled

Three files carry that section, one per analyzed package:

| File | `path:` | Covers |
|---|---|---|
| `flureadium/analysis_options.yaml` | `../flureadium_lints` | `flureadium/` minus `example/` — 42 test files |
| `flureadium_platform_interface/analysis_options.yaml` | `../flureadium_lints` | `flureadium_platform_interface/` — 27 test files |
| `flureadium/example/analysis_options.yaml` | `../../flureadium_lints` | `flureadium/example/` — 26 test files |

`plugins:` is top-level in each — a sibling of `include:`, `analyzer:` and `linter:`,
never a key under `analyzer:`. `path:` is relative to the options file holding it and
is the plugin's only reference; neither published package lists it in `pubspec.yaml`.

### Why `example` needs its own section, and an exclude

`flureadium/example` is a package nested inside `flureadium`. Only one `plugins:`
section is honoured per analyze session and the deeper one wins silently, so the two
roots compete: without an exclude, one of the two test trees goes unchecked. Measured
with `dart analyze --fatal-infos` from `flureadium/`, with a known violation in each
tree:

| Arrangement | `flureadium/test/**` | `example/test/**` |
|---|---|---|
| section in `flureadium/` only, `example/` has no options file | not checked | checked |
| section in `flureadium/` only, `example/` has options without one | checked | not checked |
| section in both roots, no exclude | not checked | checked |
| section in both roots, `flureadium/` excludes `example/**` | checked | checked, from example's own run |

Only the last row covers everything, which is why `flureadium/analysis_options.yaml`
carries

```yaml
analyzer:
  exclude:
    - example/**
```

and `example/` carries its own section. The `flureadium/` run then checks its own 42
files; `example/`'s 26 are checked by the run from `example/` itself —
`validators.conf`'s `static-plugin` row and `quality.yml`'s `Plugin lints - example`
step both do that. An ancestor's `plugins:` section does not apply at another package's
root, so without example's own section a run there reports nothing.

### The command that enforces them: `dart analyze`

`flutter analyze` does not report these diagnostics. It is not a wrapper around `dart
analyze`: it starts `dart language-server`, collects LSP diagnostics, and returns as
soon as the analysis progress token completes
(`packages/flutter_tools/lib/src/dart/analysis.dart`,
`commands/analyze_once.dart`). The plugin publishes from its own isolate after that
window closes, so the diagnostics never arrive. Measured on Flutter 3.44.7 / Dart
3.12.2 with a probe in place, same directory, same session:

| Command | cwd | Result |
|---|---|---|
| `dart analyze --fatal-infos` | `flureadium_platform_interface` | both codes reported, exit 1 |
| `flutter analyze --fatal-infos` | `flureadium_platform_interface` | `No issues found!`, exit 0 |
| `dart analyze --fatal-infos` | `flureadium` | both codes reported, exit 1 |
| `flutter analyze --fatal-infos` | `flureadium` | `No issues found!`, exit 0 |

The `flutter analyze` runs were repeated cold (35s, 91s) and warm (2.1s), so this is
not a cold-start race that a slower machine would win. Upstream:
[flutter/flutter#28327](https://github.com/flutter/flutter/issues/28327).

Both commands are wired up, doing different jobs:

- `validators.conf` — the `static` row keeps `flutter analyze`; the `static-plugin`
  row runs `dart analyze --fatal-infos` in all three packages and is what fails on a
  vacuous assertion.
- CI — `quality.yml`'s `analyze` job keeps its `Analyze - …` steps and gains three
  `Plugin lints - …` steps running `dart analyze --fatal-infos`.

Never replace a `flutter analyze` invocation with `dart analyze` on the strength of
this: the two report overlapping but different sets, and the Flutter-specific
diagnostics come from the former.
