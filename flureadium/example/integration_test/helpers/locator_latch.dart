import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the example app's `locator_href` latch — the last href delivered on
/// the text-locator event stream, or `''` before any has arrived.
///
/// Reading the pushed value rather than calling `getCurrentLocator()` is the
/// point: the pull path answers from the navigator and stays correct even if
/// the stream never delivers, so only this latch can fail when the stream
/// breaks.
String locatorHref(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('locator_href'))).data ?? '';

/// Reads the example app's `saved_locator_href` latch — the first href this
/// publication reported, or `''` before any has arrived.
///
/// Distinct from [locatorHref] on purpose: the app latches this one once per
/// open, so a test can navigate away and prove that "Go To Saved" came back.
String savedLocatorHref(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('saved_locator_href'))).data ?? '';

/// Reads the example app's `locator_progression` latch — the progression of the
/// last locator delivered, or null before any has arrived or when the locator
/// carries none.
///
/// Nullable rather than defaulting to 0.0: some resources report a locator with
/// no progression, and a 0.0 stand-in would read as "start of the resource",
/// which is a position the reader may never have been at.
double? locatorProgression(WidgetTester tester) => double.tryParse(
  tester.widget<Text>(find.byKey(const Key('locator_progression'))).data ?? '',
);

/// Reads the example app's `locator-events` counter — how many locators the
/// text-locator stream has delivered since this publication opened.
///
/// A count rather than a value, because the values repeat: a locator delivered
/// to a fresh subscriber can name the page already latched, so only a number
/// that must rise proves the delivery happened. `int.parse` throws rather than
/// defaulting, so a missing or renamed latch fails loudly instead of reading 0.
int locatorEvents(WidgetTester tester) => int.parse(
  (tester.widget<Text>(find.byKey(const Key('locator-events'))).data ?? '')
      .replaceFirst('locator-events: ', ''),
);

/// Reads the example app's `locator_toc_fragment` latch — the `toc=` heading id
/// of the last locator delivered, or `''` when none arrived and when the
/// locator that did arrive carried no fragment.
///
/// The two empty cases are deliberately not distinguished: the point of this
/// latch is that a resolved heading produces a *name*, so a test asserts on the
/// name it expects rather than on the absence of one. An assertion that only
/// checks "not empty" would pass on any fragment, including the valueless
/// `toc=` this latch exists to catch.
String locatorTocFragment(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('locator_toc_fragment'))).data ??
    '';
