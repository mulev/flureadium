import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads one of the example app's keyed debug latches.
///
/// The app renders most of them as `'<key>: <value>'` so the readout is legible
/// on screen; the prefix is stripped here so callers see the value alone. A
/// latch rendered as a bare value (the locator hrefs) is unaffected —
/// `replaceFirst` finds nothing to strip.
String _latch(WidgetTester tester, String key) {
  final text = tester.widget<Text>(find.byKey(Key(key))).data ?? '';
  return text.replaceFirst('$key: ', '');
}

/// Reads the example app's `open-generation` counter — how many publications
/// have finished opening since the app booted.
///
/// The counter moves only inside `_resetPublicationLatches()`, which runs after
/// `openPublication` returns, so a failed open cannot advance it. That is what
/// makes a bump the one signal a test can wait on that a *new* publication is
/// loaded, rather than that some reader widget happens to be mounted.
///
/// `int.tryParse ... ?? 0` rather than a throwing parse: `ensureAppShowing`
/// reads this immediately after a cold boot, when the control bar may not have
/// rendered the latch yet, and it compares the value against a later one rather
/// than trusting it on its own.
int openGeneration(WidgetTester tester) =>
    int.tryParse(_latch(tester, 'open-generation')) ?? 0;

/// Reads the example app's `publication-identifier` latch — the identifier of
/// the publication currently open, or `''` when none is.
///
/// Identity rather than title: the WebPub manifest and the bundled fixture are
/// both called "Moby-Dick", so only the identifier tells one from the other.
String publicationIdentifier(WidgetTester tester) =>
    _latch(tester, 'publication-identifier');

/// Reads the example app's `open-error` latch — the last failure an open path
/// recorded, or `''` when the last open succeeded.
///
/// Cleared by `_runOpen` whenever an open path succeeds — including the
/// load-only path, which latches failures but never resets the publication
/// latches — so a non-empty value always describes the most recent attempt. Asserting it is empty turns a silent failure into a
/// message that names its cause, instead of "found 0 widgets".
String openError(WidgetTester tester) => _latch(tester, 'open-error');
