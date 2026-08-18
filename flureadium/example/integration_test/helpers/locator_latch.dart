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
