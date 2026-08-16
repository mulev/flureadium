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
