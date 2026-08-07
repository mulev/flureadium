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
